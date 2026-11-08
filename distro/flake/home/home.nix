{
  config,
  pkgs,
  lib,
  ...
}:

# Standalone Home Manager for Debian — intentionally NO osConfig / NixOS options.
# nixGL / dankMaterialShell arrive via extraSpecialArgs into their modules.
{
  imports = [
    ./niri.nix
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
    niri
    xwayland-satellite
    wl-clipboard
  ];

  xdg.enable = true;
  xdg.mimeApps.enable = true;

  xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
    [preferred]
    default=gtk;wlr;
  '';

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    RYOKU_NIXGL_WRAPPER = "${config.home.homeDirectory}/.local/bin/ryoku-nixgl";
  };

  home.file.".local/bin/ryoku-niri-session" = {
    source = ../../session/ryoku-niri-session;
    executable = true;
  };
}
