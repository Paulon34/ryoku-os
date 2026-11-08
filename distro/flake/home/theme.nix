{ pkgs, config, ... }:

# Placeholder theme (ENTREGA A). Material You / Matugen / DMS arrive in B.
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
}
