{
  config,
  lib,
  pkgs,
  home-manager ? null,
  nixGL,
  ...
}:

# Port of ryoku-desktop Settings into Debian Modular Home Manager.
# repoPath MUST be the absolute checkout that bootstrap/HM applied — never
# guess ~/ryoku-os (VM worktrees are often ryoku-os-visual / *-fixed-* names).
#
# Qt Quick on Debian needs nixGL for host Mesa (same class of failure as DMS
# without nixGLIntel: EGL unavailable → RHI abort). Wrapper calls the store
# binary by absolute path to avoid PATH recursion.
#
# Portal / Wayland appId is org.ryoku.Settings — desktop basename must match
# (xdg.desktopEntries."org.ryoku.Settings" + package share icons/desktop).
let
  cfg = config.ryoku.settingsApply;
  username = config.home.username;
  homeDir = config.home.homeDirectory;

  repoPath = cfg.repoPath;
  flakeDir = if repoPath != "" then "${repoPath}/distro/flake" else "";
  haveRepo = repoPath != "" && builtins.substring 0 1 repoPath == "/";

  hmCli =
    if home-manager != null && home-manager ? packages then
      home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
    else
      pkgs.home-manager;

  applyHelper = pkgs.callPackage ../pkgs/ryoku-settings-apply.nix {
    inherit repoPath flakeDir;
    flakeHost = cfg.flakeHost;
    home-manager = hmCli;
  };

  settingsGui = pkgs.callPackage ../pkgs/ryoku-settings.nix {
    ryokuRepoPathDefault = repoPath;
    ryokuFlakeHostDefault = cfg.flakeHost;
  };

  nixGLIntel = nixGL.packages.${pkgs.stdenv.hostPlatform.system}.nixGLIntel;
  settingsBin = "${settingsGui}/bin/ryoku-settings";

  # Public command name stays ryoku-settings; real binary is only referenced by
  # absolute store path inside the wrapper (no re-exec of PATH ryoku-settings).
  settingsLauncher = pkgs.writeShellScriptBin "ryoku-settings" ''
    #!/usr/bin/env bash
    set -euo pipefail
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-wayland}"
    # Optional VM-only diagnostic (never set globally by modules):
    #   QT_QUICK_BACKEND=software ryoku-settings
    if [[ -n "''${RYOKU_SETTINGS_NO_NIXGL:-}" ]]; then
      exec ${settingsBin} "$@"
    fi
    exec ${nixGLIntel}/bin/nixGLIntel ${settingsBin} "$@"
  '';

  # Stable ~/.local/bin entry (session PATH puts LOCAL_BIN first) so SUPER+I /
  # Control Center / trimmed-PATH children resolve the nixGL wrapper.
  settingsLocalBin = ''
    #!/usr/bin/env bash
    set -euo pipefail
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-wayland}"
    if [[ -n "''${RYOKU_SETTINGS_NO_NIXGL:-}" ]]; then
      exec ${settingsBin} "$@"
    fi
    exec ${nixGLIntel}/bin/nixGLIntel ${settingsBin} "$@"
  '';

  polkitPolicy = pkgs.writeTextFile {
    name = "org.ryoku.settings.apply.policy";
    text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE policyconfig PUBLIC
       "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
       "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">
      <policyconfig>
        <vendor>Ryoku</vendor>
        <vendor_url>https://github.com/Paulon34/ryoku-os</vendor_url>
        <action id="org.ryoku.settings.apply">
          <description>Apply or switch Ryoku Home Manager configuration</description>
          <description xml:lang="pt_BR">Aplicar ou trocar configuração Home Manager do Ryoku</description>
          <message>Authentication is required to apply or switch Ryoku Home Manager generations.</message>
          <message xml:lang="pt_BR">É necessária autenticação para aplicar ou trocar gerações Home Manager do Ryoku.</message>
          <defaults>
            <allow_any>no</allow_any>
            <allow_inactive>auth_admin</allow_inactive>
            <allow_active>auth_admin</allow_active>
          </defaults>
          <annotate key="org.freedesktop.policykit.exec.path">${lib.getExe applyHelper}</annotate>
        </action>
      </policyconfig>
    '';
    destination = "/share/polkit-1/actions/org.ryoku.settings.apply.policy";
  };

  seedSettings = builtins.readFile ../../ryoku/settings.json;
in
{
  options.ryoku.settingsApply = {
    enable = lib.mkEnableOption "Ryoku Settings GUI + Polkit apply helper" // {
      default = true;
    };

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Absolute path to the ryoku-os checkout that this HM generation applies.
        Written by ryoku-bootstrap from REPO_ROOT. Empty disables privileged
        apply packaging (no ~/ryoku-os guess).
      '';
    };

    flakeHost = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = username;
      description = "Home Manager flake host attribute (hosts/<name>).";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.repoPath == "" || builtins.substring 0 1 cfg.repoPath == "/";
          message = "ryoku.settingsApply.repoPath must be absolute or empty";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      # hiPrio launcher shadows settingsGui's bin/ryoku-settings; settingsGui still
      # contributes share/applications/org.ryoku.Settings.desktop + hicolor icons.
      home.packages = [
        (lib.hiPrio settingsLauncher)
        settingsGui
      ]
      ++ lib.optionals haveRepo [
        applyHelper
        polkitPolicy
      ];

      # Seed user settings when missing (regular file; not HM-managed symlink).
      home.activation.ryokuSettingsSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        dest="${homeDir}/.config/ryoku/settings.json"
        mkdir -p "$(dirname "$dest")"
        if [ ! -e "$dest" ]; then
          printf '%s\n' ${lib.escapeShellArg seedSettings} >"$dest"
        fi
      '';

      home.sessionVariables = lib.mkIf haveRepo {
        RYOKU_REPO_PATH = repoPath;
      };

      home.file.".config/ryoku/settings-apply-helper" = lib.mkIf haveRepo {
        text = "${lib.getExe applyHelper}\n";
      };

      # Debug unwrapped name (absolute store path only).
      home.file.".local/bin/ryoku-settings-unwrapped" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          exec ${settingsBin} "$@"
        '';
      };

      home.file.".local/bin/ryoku-settings" = {
        executable = true;
        text = settingsLocalBin;
      };

      # Launcher self-check (read-only): XDG dataHome entry, absolute Exec/TryExec,
      # icon, keywords. Guest: desktop-file-validate + gio launch.
      home.file.".local/bin/ryoku-settings-launcher-check" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
          desk="$data_home/applications/org.ryoku.Settings.desktop"
          bin="$HOME/.local/bin/ryoku-settings"
          echo "XDG_DATA_HOME=$data_home"
          echo "desktop=$desk"
          if [[ ! -f "$desk" ]]; then
            echo "FAIL: missing canonical desktop entry"
            exit 1
          fi
          if [[ ! -x "$bin" ]]; then
            echo "FAIL: missing ~/.local/bin/ryoku-settings"
            exit 1
          fi
          grep -Eq "^Exec=$bin($|[[:space:]])" "$desk" || {
            echo "FAIL: Exec must be absolute $bin"
            exit 1
          }
          grep -Eq "^TryExec=$bin$" "$desk" || {
            echo "FAIL: TryExec must be absolute $bin"
            exit 1
          }
          grep -Fq 'Icon=org.ryoku.Settings' "$desk" || {
            echo "FAIL: Icon=org.ryoku.Settings required"
            exit 1
          }
          grep -Eqi 'Keywords=.*Ryoku' "$desk" || {
            echo "FAIL: Keywords must include Ryoku"
            exit 1
          }
          if command -v desktop-file-validate >/dev/null 2>&1; then
            desktop-file-validate "$desk"
          else
            echo "WARN: desktop-file-validate not installed"
          fi
          # Duplicate legacy id shadows search — warn only.
          if [[ -f "$data_home/applications/ryoku-settings.desktop" ]]; then
            echo "WARN: legacy ryoku-settings.desktop still present (prefer org.ryoku.Settings)"
          fi
          echo "PASS: launcher desktop contract"
        '';
      };

      # Adopt/backup a manually created entry without clobbering user content.
      # One canonical managed ID: org.ryoku.Settings (never ryoku-settings.desktop).
      home.activation.ryokuSettingsDesktopAdopt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        data_home="''${XDG_DATA_HOME:-${homeDir}/.local/share}"
        apps="$data_home/applications"
        stamp="$apps/.ryoku-settings-desktop.managed"
        backup_dir="${homeDir}/.local/state/ryoku/desktop-backup"
        run mkdir -p "$apps" "$backup_dir"
        # Backup legacy/manual duplicates once, then remove the legacy basename.
        if [ -f "$apps/ryoku-settings.desktop" ]; then
          ts=$(date -u +%Y%m%dT%H%M%SZ)
          run cp -a "$apps/ryoku-settings.desktop" "$backup_dir/ryoku-settings.desktop.$ts"
          run rm -f "$apps/ryoku-settings.desktop"
          echo "Ryoku Settings: backed up legacy ryoku-settings.desktop → $backup_dir"
        fi
        # If a non-HM org.ryoku.Settings.desktop exists before linkGeneration,
        # keep a copy (HM will replace the live file on the next switch).
        if [ -f "$apps/org.ryoku.Settings.desktop" ] && [ ! -e "$stamp" ]; then
          if ! grep -Fq 'X-Ryoku-Managed=1' "$apps/org.ryoku.Settings.desktop" 2>/dev/null; then
            ts=$(date -u +%Y%m%dT%H%M%SZ)
            run cp -a "$apps/org.ryoku.Settings.desktop" \
              "$backup_dir/org.ryoku.Settings.desktop.manual.$ts"
            echo "Ryoku Settings: backed up manual org.ryoku.Settings.desktop"
          fi
        fi
        run printf '1\n' >"$stamp"
        if command -v update-desktop-database >/dev/null 2>&1; then
          run update-desktop-database "$apps" || true
        fi
      '';

      # Canonical FreeDesktop id for portals (matches Qt appId org.ryoku.Settings).
      # Do not emit ryoku-settings.desktop — that breaks portal app lookup.
      # Absolute Exec/TryExec so DMS DesktopEntries indexing works even when the
      # launcher process tree has a trimmed PATH (GDM + nixGL wrapper).
      xdg.desktopEntries."org.ryoku.Settings" = {
        name = "Ryoku Settings";
        genericName = "Settings";
        comment = "Configure Ryoku desktop appearance and system";
        exec = "${homeDir}/.local/bin/ryoku-settings";
        icon = "org.ryoku.Settings";
        terminal = false;
        categories = [
          "Settings"
          "DesktopSettings"
          "System"
        ];
        startupNotify = true;
        settings = {
          "Name[pt_BR]" = "Configurações Ryoku";
          "GenericName[pt_BR]" = "Configurações do sistema";
          "Comment[pt_BR]" = "Configurar a aparência e o sistema Ryoku";
          TryExec = "${homeDir}/.local/bin/ryoku-settings";
          NoDisplay = "false";
          StartupWMClass = "org.ryoku.Settings";
          Keywords = "Ryoku;Settings;System;Configurações;Preferências;Control Center;Painel;Ryoku Settings;";
          "Keywords[pt_BR]" = "Ryoku;Configurações;Preferências;Sistema;Painel;Control Center;";
          # Marker so activation can tell managed vs manual copies apart.
          X-Ryoku-Managed = "1";
          X-Ryoku-Launcher = "org.ryoku.Settings";
        };
        # Desktop actions: open Ryoku Settings, or native DMS shell settings
        # (does not remove Control Center / SUPER+,).
        actions = {
          Open = {
            name = "Open Ryoku Settings";
            exec = "${homeDir}/.local/bin/ryoku-settings";
          };
          DmsShell = {
            name = "Open DMS shell settings";
            exec = "${homeDir}/.local/bin/ryoku-dms-ipc settings toggle";
          };
        };
      };

      # MIME comfort for local packages (Thunar double-click). Debian-native
      # handlers only — never replace Flatpak/apt policy beyond defaults.
      xdg.mimeApps.defaultApplications = {
        "application/vnd.debian.binary-package" = [ "gdebi.desktop" ];
        "application/x-deb" = [ "gdebi.desktop" ];
        "application/vnd.flatpak" = [ "org.gnome.Software.desktop" "org.kde.discover.desktop" ];
        "application/vnd.flatpak.ref" = [ "org.gnome.Software.desktop" "org.kde.discover.desktop" ];
        "application/vnd.appimage" = [ "appimagelauncher.desktop" "appimagekit.desktop" ];
        "application/x-iso9660-appimage" = [ "appimagelauncher.desktop" "appimagekit.desktop" ];
      };
    })
  ];
}
