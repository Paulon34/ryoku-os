{
  config,
  pkgs,
  lib,
  ...
}:

# Standalone Home Manager for Debian — intentionally NO osConfig / NixOS options.
# nixGL arrives via extraSpecialArgs into ./nixgl.nix only.
{
  imports = [
    # profiles.nix is pulled via flake modules = [ ./modules ... ]; keep home lean.
    ./niri.nix
    ./kitty.nix
    ./fuzzel.nix
    ./theme.nix
    ./nixgl.nix
  ];

  # Surface Jarvis default for shells / later ryoku-cli.
  home.sessionVariables.RYOKU_JARVIS = lib.mkDefault (
    if config.ryoku.profile.jarvis then "1" else "0"
  );
  home.sessionVariables.RYOKU_EDITION = config.ryoku.profile.edition;
  home.sessionVariables.RYOKU_VISUAL_PROFILE = config.ryoku.profile.visual;
  home.sessionVariables.RYOKU_SHELL_STYLE = config.ryoku.profile.shellStyle;

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Session-facing packages from Nix when APT equivalents are missing or weaker.
  home.packages = with pkgs; [
    niri
    xwayland-satellite # XWayland integration helper used by modern Niri
    wl-clipboard
    grim
    slurp
  ];

  # Portals: prefer user services when systemd --user is available on Debian.
  xdg.enable = true;
  xdg.mimeApps.enable = true;

  xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
    [preferred]
    default=gtk;wlr;
  '';

  # Environment for mixed APT + Nix graphics stacks.
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    # Hint for tools wrapping GL apps (see nixgl.nix).
    RYOKU_NIXGL_WRAPPER = "${config.home.homeDirectory}/.local/bin/ryoku-nixgl";
  };

  home.file.".local/bin/ryoku-niri-session" = {
    source = ../../session/ryoku-niri-session;
    executable = true;
  };
}
