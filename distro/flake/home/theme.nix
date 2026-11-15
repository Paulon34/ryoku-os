{ pkgs, config, lib, ... }:

# GTK/Qt theme parity with ryoku-desktop home/theme.nix (Niri/Debian).
# Wallpapers + Matugen live in matugen.nix.
#
# Thunar (APT GTK3) stays light when only dconf prefer-dark is set and
# GTK_THEME never reaches compositor children (GDM skips HM sessionVariables).
# Prefer-dark + Adwaita:dark + portal + env propagation cover GTK3 and
# GTK4/libadwaita; GTK_THEME alone is not the sole fix.
let
  cursor = (import ../../ryoku/lib.nix { inherit lib; }).pointerCursor;
  # Debian papirus-icon-theme ships Papirus-Dark; Nix package matches.
  iconThemeName = "Papirus-Dark";
  # Adwaita:dark = GTK dark variant syntax (works for host Adwaita without a
  # separate Adwaita-dark tree). Theme name Adwaita-dark still used in settings.ini
  # when gnome-themes-extra is on XDG_DATA_DIRS / /usr/share/themes.
  gtkThemeEnv = "Adwaita:dark";
  gtkThemeSettings = "Adwaita-dark";
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

  # GTK4/libadwaita and the XDG Settings portal use the desktop color
  # scheme preference, not just the GTK3 theme name.
  dconf.enable = true;
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = gtkThemeSettings;
    icon-theme = iconThemeName;
    cursor-theme = cursor.name;
    cursor-size = cursor.size;
  };

  gtk = {
    enable = true;
    theme = {
      name = gtkThemeSettings;
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = iconThemeName;
      package = pkgs.papirus-icon-theme;
    };
    # Preserve GTK4 theme explicitly for Home Manager stateVersion 25.11.
    gtk4.theme = config.gtk.theme;
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-theme-name = gtkThemeSettings;
      gtk-icon-theme-name = iconThemeName;
      gtk-cursor-theme-name = cursor.name;
      gtk-cursor-theme-size = cursor.size;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-theme-name = gtkThemeSettings;
      gtk-icon-theme-name = iconThemeName;
      gtk-cursor-theme-name = cursor.name;
      gtk-cursor-theme-size = cursor.size;
    };
    # Material You accents from Matugen (ryoku-colors.css); surfaces stay dark.
    gtk3.extraCss = ''
      @import url("file://${config.home.homeDirectory}/.config/gtk-3.0/ryoku-colors.css");
    '';
    gtk4.extraCss = ''
      @import url("file://${config.home.homeDirectory}/.config/gtk-4.0/ryoku-colors.css");
    '';
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };

  home.sessionVariables = {
    GTK_THEME = gtkThemeEnv;
    # Mirror pointerCursor for shells/apps that only read env (Firefox, Kitty,
    # Flatpak hosts). Session wrappers also export these for GDM.
    XCURSOR_THEME = cursor.name;
    XCURSOR_SIZE = toString cursor.size;
    QT_STYLE_OVERRIDE = "adwaita-dark";
    # Icon theme for toolkits that ignore settings.ini (some Flatpaks/Qt).
    XDG_ICON_THEME = iconThemeName;
  };

  # D-Bus / systemd --user activated apps do not inherit Hyprland env=.
  # environment.d is read by pam_env / systemd user manager on login.
  xdg.configFile."environment.d/90-ryoku-dark.conf".text = ''
    GTK_THEME=${gtkThemeEnv}
    QT_STYLE_OVERRIDE=adwaita-dark
    XCURSOR_THEME=${cursor.name}
    XCURSOR_SIZE=${toString cursor.size}
    XDG_ICON_THEME=${iconThemeName}
  '';

  # Flatpak sandboxes do not inherit host cursor/GTK themes unless overridden.
  # Idempotent user override — never publishes proprietary themes or host paths
  # beyond shared theme/icon/cursor names.
  home.activation.ryokuFlatpakTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if command -v flatpak >/dev/null 2>&1; then
      run flatpak override --user \
        --env=XCURSOR_THEME=${lib.escapeShellArg cursor.name} \
        --env=XCURSOR_SIZE=${lib.escapeShellArg (toString cursor.size)} \
        --env=GTK_THEME=${lib.escapeShellArg gtkThemeEnv} \
        --env=XDG_ICON_THEME=${lib.escapeShellArg iconThemeName} \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-config/gtk-4.0:ro \
        || echo "WARN: flatpak theme override failed (non-fatal)" >&2
    fi
  '';

  # Seed empty Matugen CSS so @import does not fail before first wallpaper.
  home.activation.ryokuGtkColorSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for dir in gtk-3.0 gtk-4.0; do
      dest="$HOME/.config/$dir/ryoku-colors.css"
      run mkdir -p "$HOME/.config/$dir"
      if [ ! -f "$dest" ]; then
        run printf '%s\n' '/* Ryoku dark seed — replaced by Matugen */' >"$dest"
      fi
    done
  '';

  home.packages = with pkgs; [
    adwaita-icon-theme
    gnome-themes-extra
    papirus-icon-theme
  ];
}
