{ pkgs, config, lib, ... }:

# GTK/Qt theme parity with ryoku-desktop home/theme.nix (Niri/Debian).
# Wallpapers + Matugen live in matugen.nix.
let
  cursor = (import ../../ryoku/lib.nix { inherit lib; }).pointerCursor;
in
{
  # Same pointer theme as the original Ryoku NixOS desktop.
  home.pointerCursor = {
    enable = true;
    inherit (cursor) name size;
    package = pkgs.${cursor.package};
    gtk.enable = true;
    x11.enable = false;
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    # Preserve GTK4 theme explicitly for Home Manager stateVersion 25.11.
    gtk4.theme = config.gtk.theme;
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };

  home.sessionVariables = {
    GTK_THEME = "Adwaita:dark";
  };

  home.packages = with pkgs; [
    adwaita-icon-theme
    gnome-themes-extra
  ];
}
