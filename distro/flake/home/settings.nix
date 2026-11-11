{
  config,
  lib,
  pkgs,
  home-manager ? null,
  ...
}:

# Port of ryoku-desktop Settings into Debian Modular Home Manager.
# repoPath MUST be the absolute checkout that bootstrap/HM applied — never
# guess ~/ryoku-os (VM worktrees are often ryoku-os-visual / *-fixed-* names).
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
      # GUI always available; privileged helper only when repoPath is approved.
      home.packages = [ settingsGui ] ++ lib.optionals haveRepo [
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

      xdg.desktopEntries.ryoku-settings = {
        name = "Ryoku Settings";
        genericName = "Settings";
        comment = "Configure Ryoku desktop appearance and system";
        exec = "ryoku-settings";
        icon = "org.ryoku.Settings";
        terminal = false;
        categories = [
          "Settings"
          "DesktopSettings"
        ];
        startupNotify = true;
        settings = {
          StartupWMClass = "org.ryoku.Settings";
        };
      };
    })
  ];
}
