{
  config,
  pkgs,
  lib,
  dankMaterialShell,
  nixGL,
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
    pkgs.quickshell # DMS v1.5.3 launches `qs -p <dms-qml>` at runtime.
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

  # The tested GDM session invokes 'niri --session' directly, not via
  # niri-session / niri.service; graphical-session.target is not guaranteed
  # active in that case. Spawn DMS from Niri after WAYLAND_DISPLAY is ready.
  # Do NOT also enable a competing systemd user service (double instance).
  # Quickshell needs the same Mesa wrapper as the Nix-built compositor on Debian.
  home.file.".local/bin/ryoku-start-dms" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # GDM/Niri may not inherit the Home Manager profile PATH. The DMS Go
      # launcher executes `qs` by name, so provide Quickshell explicitly.
      export PATH="${lib.makeBinPath [ pkgs.quickshell ]}:$PATH"
      exec "${nixGL.packages.${pkgs.stdenv.hostPlatform.system}.nixGLIntel}/bin/nixGLIntel" "${dmsPackage}/bin/dms" run
    '';
  };
}
