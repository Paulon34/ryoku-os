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
    # Mirror pointerCursor for shells/apps that only read env (Firefox, Kitty,
    # Flatpak hosts). Session wrappers also export these for GDM.
    XCURSOR_THEME = cursor.name;
    XCURSOR_SIZE = toString cursor.size;
  };

  # Flatpak sandboxes do not inherit host cursor themes unless overridden.
  # Idempotent user override — never publishes proprietary themes or host paths
  # beyond the shared Bibata package name/size.
  home.activation.ryokuFlatpakCursor = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if command -v flatpak >/dev/null 2>&1; then
      run flatpak override --user \
        --env=XCURSOR_THEME=${lib.escapeShellArg cursor.name} \
        --env=XCURSOR_SIZE=${lib.escapeShellArg (toString cursor.size)} \
        || echo "WARN: flatpak cursor override failed (non-fatal)" >&2
    fi
  '';

  home.packages = with pkgs; [
    adwaita-icon-theme
    gnome-themes-extra
  ];
}
