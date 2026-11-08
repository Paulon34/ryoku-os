{ pkgs, config, ... }:

# GTK/Qt theme parity with ryoku-desktop home/theme.nix (Niri/Debian).
# Wallpapers + Matugen live in matugen.nix; SDDM astronaut QML is not ported.
{
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
