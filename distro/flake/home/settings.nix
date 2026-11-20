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

  # Canonical contract path: $XDG_DATA_HOME/applications/… (launcher-check,
  # DMS user dir, portals). Note: xdg.desktopEntries alone only installs a
  # hiPrio makeDesktopItem into the HM profile share (XDG_DATA_DIRS) — it does
  # NOT create ~/.local/share/applications/org.ryoku.Settings.desktop. We also
  # emit xdg.dataFile so the FreeDesktop dataHome path exists after switch.
  hmDataHome = config.xdg.dataHome;
  hmDesktop = "${hmDataHome}/applications/org.ryoku.Settings.desktop";
  settingsDesktopText = ''
    [Desktop Entry]
    Type=Application
    Version=1.5
    Name=Ryoku Settings
    Name[pt_BR]=Configurações Ryoku
    GenericName=Settings
    GenericName[pt_BR]=Configurações do sistema
    Comment=Configure Ryoku desktop appearance and system
    Comment[pt_BR]=Configurar a aparência e o sistema Ryoku
    Exec=${homeDir}/.local/bin/ryoku-settings
    TryExec=${homeDir}/.local/bin/ryoku-settings
    Icon=org.ryoku.Settings
    Terminal=false
    Categories=Settings;DesktopSettings;System;
    Keywords=Ryoku;Settings;System;Configurações;Preferências;Control Center;Painel;Ryoku Settings;
    Keywords[pt_BR]=Ryoku;Configurações;Preferências;Sistema;Painel;Control Center;
    StartupNotify=true
    StartupWMClass=org.ryoku.Settings
    NoDisplay=false
    X-Ryoku-Managed=1
    X-Ryoku-Launcher=org.ryoku.Settings
    Actions=Open;DmsShell;

    [Desktop Action Open]
    Name=Open Ryoku Settings
    Exec=${homeDir}/.local/bin/ryoku-settings

    [Desktop Action DmsShell]
    Name=Open DMS shell settings
    Exec=${homeDir}/.local/bin/ryoku-dms-ipc settings toggle
  '';
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

      # Launcher self-check (read-only): HM dataHome entry first (matches
      # xdg.desktopEntries), then $XDG_DATA_HOME if it diverges. Absolute
      # Exec/TryExec, icon, keywords. Guest: desktop-file-validate + gio launch.
      home.file.".local/bin/ryoku-settings-launcher-check" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          hm_desk=${lib.escapeShellArg hmDesktop}
          env_home="''${XDG_DATA_HOME:-}"
          env_desk=""
          if [[ -n "$env_home" ]]; then
            env_desk="$env_home/applications/org.ryoku.Settings.desktop"
          fi
          bin="$HOME/.local/bin/ryoku-settings"
          # Profile share is where xdg.desktopEntries alone lands (not dataHome).
          prof_desk=""
          for cand in \
            "$HOME/.local/state/nix/profiles/home-manager/home-path/share/applications/org.ryoku.Settings.desktop" \
            "$HOME/.nix-profile/share/applications/org.ryoku.Settings.desktop"; do
            if [[ -e "$cand" || -L "$cand" ]]; then
              prof_desk="$cand"
              break
            fi
          done
          echo "hm_desktop=$hm_desk"
          echo "XDG_DATA_HOME=''${env_home:-(unset → $HOME/.local/share)}"
          desk=""
          if [[ -e "$hm_desk" || -L "$hm_desk" ]]; then
            desk="$hm_desk"
          elif [[ -n "$env_desk" && ( -e "$env_desk" || -L "$env_desk" ) ]]; then
            echo "WARN: canonical entry not under HM dataHome; using XDG_DATA_HOME copy"
            desk="$env_desk"
          elif [[ -n "$prof_desk" ]]; then
            echo "WARN: dataHome desktop missing; using profile share entry"
            desk="$prof_desk"
          fi
          if [[ -z "$desk" ]]; then
            echo "FAIL: missing canonical desktop entry"
            echo "  expected: $hm_desk"
            [[ -n "$env_desk" ]] && echo "  also looked: $env_desk"
            echo "  also looked: HM/nix profile share/applications"
            exit 1
          fi
          echo "desktop=$desk"
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
          if [[ -f "$(dirname "$desk")/ryoku-settings.desktop" ]]; then
            echo "WARN: legacy ryoku-settings.desktop still present (prefer org.ryoku.Settings)"
          fi
          echo "PASS: launcher desktop contract"
        '';
      };

      # Adopt/backup a manually created entry WITHOUT clobbering user content.
      # MUST run before checkLinkTargets: a regular-file desktop entry where HM
      # wants a symlink makes activation fail. Backup then remove/move aside.
      # One canonical managed ID: org.ryoku.Settings (never ryoku-settings.desktop).
      # Always operate on HM dataHome (xdg.desktopEntries target), and also clear
      # blockers under a divergent XDG_DATA_HOME so linkGeneration is not skipped.
      home.activation.ryokuSettingsDesktopAdopt = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        hm_apps=${lib.escapeShellArg (hmDataHome + "/applications")}
        env_home="''${XDG_DATA_HOME:-}"
        backup_dir="${homeDir}/.local/state/ryoku/desktop-backup"
        run mkdir -p "$hm_apps" "$backup_dir"
        ts=$(date -u +%Y%m%dT%H%M%SZ)

        adopt_desktop_dir() {
          local apps="$1"
          local stamp="$apps/.ryoku-settings-desktop.managed"
          run mkdir -p "$apps"
          if [ -f "$apps/ryoku-settings.desktop" ]; then
            run cp -a "$apps/ryoku-settings.desktop" "$backup_dir/ryoku-settings.desktop.$ts"
            run rm -f "$apps/ryoku-settings.desktop"
            echo "Ryoku Settings: backed up legacy ryoku-settings.desktop → $backup_dir"
          fi
          # Broken HM symlink blocks a clean relink.
          if [ -L "$apps/org.ryoku.Settings.desktop" ] && [ ! -e "$apps/org.ryoku.Settings.desktop" ]; then
            run rm -f "$apps/org.ryoku.Settings.desktop"
            echo "Ryoku Settings: removed broken org.ryoku.Settings.desktop symlink"
          fi
          # Manual org.ryoku.Settings.desktop (non-symlink) blocks HM linkGeneration.
          if [ -e "$apps/org.ryoku.Settings.desktop" ] && [ ! -L "$apps/org.ryoku.Settings.desktop" ]; then
            if ! grep -Fq 'X-Ryoku-Managed=1' "$apps/org.ryoku.Settings.desktop" 2>/dev/null; then
              run cp -a "$apps/org.ryoku.Settings.desktop" \
                "$backup_dir/org.ryoku.Settings.desktop.manual.$ts"
              echo "Ryoku Settings: backed up manual org.ryoku.Settings.desktop"
            else
              run cp -a "$apps/org.ryoku.Settings.desktop" \
                "$backup_dir/org.ryoku.Settings.desktop.pre-hm.$ts" || true
            fi
            run rm -f "$apps/org.ryoku.Settings.desktop"
          fi
          run printf '1\n' >"$stamp"
        }

        adopt_desktop_dir "$hm_apps"
        if [[ -n "$env_home" && "$env_home" != ${lib.escapeShellArg hmDataHome} ]]; then
          echo "Ryoku Settings: also adopting under divergent XDG_DATA_HOME=$env_home"
          adopt_desktop_dir "$env_home/applications"
        fi
      '';

      # After links exist: require canonical HM entry, then refresh mime cache.
      home.activation.ryokuSettingsDesktopVerify = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        desk=${lib.escapeShellArg hmDesktop}
        bin="${homeDir}/.local/bin/ryoku-settings"
        if [ ! -e "$desk" ]; then
          echo "ERROR: missing canonical desktop entry after linkGeneration: $desk" >&2
          echo "  xdg.enable must be true; xdg.desktopEntries.\"org.ryoku.Settings\" must link here." >&2
          exit 1
        fi
        if [ ! -x "$bin" ]; then
          echo "ERROR: missing ~/.local/bin/ryoku-settings after linkGeneration" >&2
          exit 1
        fi
        grep -Eq "^Exec=$bin($|[[:space:]])" "$desk" || {
          echo "ERROR: $desk Exec must be absolute $bin" >&2
          exit 1
        }
        grep -Eq "^TryExec=$bin$" "$desk" || {
          echo "ERROR: $desk TryExec must be absolute $bin" >&2
          exit 1
        }
        echo "Ryoku Settings: verified canonical desktop entry at $desk"
      '';

      home.activation.ryokuSettingsDesktopDatabase = lib.hm.dag.entryAfter [ "ryokuSettingsDesktopVerify" ] ''
        apps=${lib.escapeShellArg (hmDataHome + "/applications")}
        if command -v update-desktop-database >/dev/null 2>&1; then
          run update-desktop-database "$apps" || true
        fi
      '';

      # Canonical FreeDesktop id for portals (matches Qt appId org.ryoku.Settings).
      # Do not emit ryoku-settings.desktop — that breaks portal app lookup.
      # Absolute Exec/TryExec so DMS DesktopEntries indexing works even when the
      # launcher process tree has a trimmed PATH (GDM + nixGL wrapper).
      #
      # dataFile → ~/.local/share/applications (XDG_DATA_HOME; launcher-check).
      # desktopEntries → hiPrio profile share override of the package's relative
      # Exec=ryoku-settings desktop (XDG_DATA_DIRS / home-path).
      xdg.dataFile."applications/org.ryoku.Settings.desktop".text = settingsDesktopText;

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
