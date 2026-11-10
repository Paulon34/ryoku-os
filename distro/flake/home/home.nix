{
  config,
  pkgs,
  lib,
  ...
}:

# Standalone Home Manager for Debian — intentionally NO osConfig / NixOS options.
# nixGL / dankMaterialShell arrive via extraSpecialArgs into their modules.
# Compositor modules self-gate on ryoku.profile.compositor (hyprland | niri).
{
  imports = [
    ./session-helpers.nix
    ./niri.nix
    ./hyprland.nix
    ./kitty.nix
    ./fuzzel.nix
    ./theme.nix
    ./nixgl.nix
    ./dms.nix
    ./matugen.nix
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    wl-clipboard
  ];

  xdg.enable = true;
  xdg.mimeApps.enable = true;

  xdg.configFile."xdg-desktop-portal/portals.conf".text =
    if config.ryoku.profile.compositor == "hyprland" then
      ''
        [preferred]
        default=hyprland;gtk;wlr;
      ''
    else
      ''
        [preferred]
        default=gtk;wlr;
      '';

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    RYOKU_NIXGL_WRAPPER = "${config.home.homeDirectory}/.local/bin/ryoku-nixgl";
    RYOKU_JARVIS = lib.mkDefault (if config.ryoku.profile.jarvis then "1" else "0");
    RYOKU_EDITION = config.ryoku.profile.edition;
    RYOKU_VISUAL_PROFILE = config.ryoku.profile.visual;
    RYOKU_SHELL_STYLE = config.ryoku.profile.shellStyle;
    RYOKU_COMPOSITOR = config.ryoku.profile.compositor;
  };
}
