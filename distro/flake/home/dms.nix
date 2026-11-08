{
  config,
  pkgs,
  lib,
  dankMaterialShell,
  ...
}:

# DankMaterialShell on Niri — standalone HM (no osConfig).
# Visual styles Quattro (default) / Islands via settings + patched package.
let
  shellStyle = config.ryoku.profile.shellStyle;
  quattro = shellStyle == "quattro";

  dmsPkgs = dankMaterialShell.packages.${pkgs.stdenv.hostPlatform.system};

  dmsPackage = pkgs.callPackage ../pkgs/dms-shell-ryoku.nix {
    dms-shell = dmsPkgs.dms-shell;
    ryokuSettingsJson = "${config.home.homeDirectory}/.config/ryoku/settings.json";
    ryokuShellStyle = shellStyle;
  };

  # Bar defaults inspired by ryoku-desktop home/dms.nix (no osConfig).
  styleBar =
    if quattro then
      {
        noBackground = false;
        transparency = 0.96;
        widgetTransparency = 0;
        spacing = 0;
        innerPadding = 1;
        widgetPadding = 6;
        fontScale = 1.1;
        squareCorners = true;
      }
    else
      {
        noBackground = true;
        transparency = 0.85;
        widgetTransparency = 0.7;
        spacing = 8;
        innerPadding = 4;
        widgetPadding = 8;
        fontScale = 1.0;
        squareCorners = false;
      };

  styleSettings =
    if quattro then
      {
        cornerRadius = 8;
        popupTransparency = 0.97;
        notificationPopupShadowEnabled = false;
        dankLauncherV2BorderEnabled = false;
        modalDarkenBackground = true;
        powerMenuGridLayout = false;
        lockScreenShowProfileImage = false;
        launcherLogoMode = "os";
      }
    else
      {
        cornerRadius = 16;
        launcherLogoMode = "apps";
        notificationPopupShadowEnabled = true;
        lockScreenShowProfileImage = true;
        popupTransparency = 0.88;
      };
in
{
  home.packages = [
    dmsPackage
    pkgs.matugen
  ];

  # Minimal settings seed — DMS first-run patch + Ryoku bar profile.
  xdg.configFile."DankMaterialShell/settings.json".text = builtins.toJSON (
    styleSettings
    // {
      barConfigs = {
        default = styleBar;
      };
      currentWallpaper = "${config.home.homeDirectory}/.local/share/wallpapers/ryoku-night.jpg";
    }
  );

  xdg.configFile."ryoku/settings.json".text = builtins.toJSON {
    appearance = {
      shellStyle = shellStyle;
      visualProfile = "balanced";
    };
  };

  # Start DMS with the compositor session (Niri).
  systemd.user.services.ryoku-dms = {
    Unit = {
      Description = "Ryoku DankMaterialShell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${dmsPackage}/bin/dms run --session";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
