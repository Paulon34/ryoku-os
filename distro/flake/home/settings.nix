{
  config,
  lib,
  pkgs,
  home-manager ? null,
  ...
}:

# Port of ryoku-desktop Settings into Debian Modular Home Manager.
# Installs the Qt GUI + privileged apply helper + Polkit action + seed settings.
let
  cfg = config.ryoku.settingsApply;
  username = config.home.username;
  homeDir = config.home.homeDirectory;

  # Default checkout path used by bootstrap / VM docs.
  defaultRepo = "${homeDir}/ryoku-os";
  repoPath = if cfg.repoPath != "" then cfg.repoPath else defaultRepo;
  flakeDir = "${repoPath}/distro/flake";

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
      description = "Absolute path to the ryoku-os checkout (empty → ~/ryoku-os).";
    };

    flakeHost = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9_-]+";
      default = username;
      description = "Home Manager flake host attribute (hosts/<name>).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      settingsGui
      applyHelper
      polkitPolicy
    ];

    # Seed user settings when missing (never overwrite user edits).
    home.activation.ryokuSettingsSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      dest="${homeDir}/.config/ryoku/settings.json"
      mkdir -p "$(dirname "$dest")"
      if [ ! -e "$dest" ]; then
        printf '%s\n' ${lib.escapeShellArg seedSettings} >"$dest"
      fi
    '';

    # Helper path for ApplyController::helperPathFile (Debian: user-writable mirror + system).
    # System /etc/ryoku/* requires bootstrap root; also write under XDG for detection fallback.
    home.file.".config/ryoku/settings-apply-helper".text = "${lib.getExe applyHelper}\n";

    home.sessionVariables.RYOKU_REPO_PATH = repoPath;

    # Desktop launcher is installed by the package; also expose a bin wrapper name.
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
  };
}
