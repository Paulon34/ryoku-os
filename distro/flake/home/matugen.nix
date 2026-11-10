{ config, pkgs, lib, ... }:

# Material You via Matugen — wallpaper → DMS Theme + compositor colors.
# Desktop parity: change-wallpaper is DMS-first (single wallpaper owner).
# Hyprland: ~/.config/ryoku/hyprland-colors.conf (Islands vs Quattro template).
# Niri recovery: colors.kdl + dms/colors.kdl (unchanged from #27).
let
  quattro = config.ryoku.profile.shellStyle == "quattro";
  compositor = config.ryoku.profile.compositor;

  niriColorsFallback = pkgs.writeText "ryoku-niri-colors-fallback.kdl" ''
    // Ryoku Appearance Engine — Niri focus-ring fallback (pre-Matugen).
    layout {
        focus-ring {
            width 2
            active-color "#8a9099"
            inactive-color "#3a3a3a"
        }
    }
  '';

  dmsNiriColorsFallback = pkgs.writeText "ryoku-dms-niri-colors-fallback.kdl" ''
    // Ryoku seed — overwritten by DMS matugen on wallpaper set.
    layout {
        background-color "transparent"
        focus-ring {
            active-color "#8a9099"
            inactive-color "#3a3a3a"
            urgent-color "#c44"
        }
        border {
            active-color "#8a9099"
            inactive-color "#3a3a3a"
            urgent-color "#c44"
        }
    }
  '';

  hyprlandColorsFallback = pkgs.writeText "ryoku-hyprland-colors-fallback.conf" ''
    general {
        col.active_border = rgba(8a9099cc)
        col.inactive_border = rgba(3a3a3a80)
    }
  '';

  hyprlandTemplate =
    if quattro then
      ./matugen/templates/ryoku-hyprland-quattro.conf
    else
      ./matugen/templates/ryoku-hyprland.conf;
in
{
  home.packages = [ pkgs.matugen ];

  home.file.".local/share/wallpapers" = {
    source = ../../assets/wallpapers;
    recursive = true;
  };

  home.file.".config/matugen/config.toml".text = ''
    [config]
    reload_apps = true

    [templates.ryoku_palette_json]
    input_path = "${config.home.homeDirectory}/.config/matugen/templates/ryoku-palette.json"
    output_path = "${config.home.homeDirectory}/.config/ryoku/palette.json"

    [templates.ryoku_palette_css]
    input_path = "${config.home.homeDirectory}/.config/matugen/templates/ryoku-palette.css"
    output_path = "${config.home.homeDirectory}/.config/ryoku/palette.css"

    [templates.ryoku_niri]
    input_path = "${config.home.homeDirectory}/.config/matugen/templates/ryoku-niri-colors.kdl"
    output_path = "${config.home.homeDirectory}/.config/niri/colors.kdl"
    post_hook = "niri msg action load-config-file || true"

    [templates.ryoku_hyprland]
    input_path = "${config.home.homeDirectory}/.config/matugen/templates/ryoku-hyprland.conf"
    output_path = "${config.home.homeDirectory}/.config/ryoku/hyprland-colors.conf"
    post_hook = "hyprctl reload || true"
  '';

  home.file.".config/matugen/templates/ryoku-palette.json".source = ./matugen/templates/ryoku-palette.json;
  home.file.".config/matugen/templates/ryoku-palette.css".source = ./matugen/templates/ryoku-palette.css;
  home.file.".config/matugen/templates/ryoku-niri-colors.kdl".source = ./matugen/templates/ryoku-niri-colors.kdl;
  # Style-selected Hyprland border template (Islands solid / Quattro gradient).
  home.file.".config/matugen/templates/ryoku-hyprland.conf".source = hyprlandTemplate;
  home.file.".config/matugen/templates/ryoku-hyprland-islands.conf".source =
    ./matugen/templates/ryoku-hyprland.conf;
  home.file.".config/matugen/templates/ryoku-hyprland-quattro.conf".source =
    ./matugen/templates/ryoku-hyprland-quattro.conf;

  home.activation.ensureRyokuNiriColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/niri/dms" "$HOME/.config/ryoku" "$HOME/.config/hypr"
    if [ ! -e "$HOME/.config/niri/colors.kdl" ]; then
      run install -m 644 ${niriColorsFallback} "$HOME/.config/niri/colors.kdl"
    fi
    if [ ! -e "$HOME/.config/niri/dms/colors.kdl" ]; then
      run install -m 644 ${dmsNiriColorsFallback} "$HOME/.config/niri/dms/colors.kdl"
    fi
    if [ ! -e "$HOME/.config/ryoku/hyprland-colors.conf" ]; then
      run install -m 644 ${hyprlandColorsFallback} "$HOME/.config/ryoku/hyprland-colors.conf"
    fi
    wallpaper="$HOME/.local/share/wallpapers/ryoku-night.jpg"
    if [ -f "$wallpaper" ] && [ ! -e "$HOME/.config/ryoku/current-wallpaper" ]; then
      run ln -sfn "$wallpaper" "$HOME/.config/ryoku/current-wallpaper"
    fi
  '';

  home.file.".local/bin/change-wallpaper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      WALL_DIR="${config.home.homeDirectory}/.local/share/wallpapers"
      mapfile -t walls < <(find -L "$WALL_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort)
      [[ ''${#walls[@]} -gt 0 ]] || { echo "no wallpapers in $WALL_DIR" >&2; exit 1; }
      pick=''${walls[RANDOM % ''${#walls[@]}]}
      mkdir -p "${config.home.homeDirectory}/.config/ryoku" \
        "${config.home.homeDirectory}/.config/niri/dms"
      ln -sfn "$pick" "${config.home.homeDirectory}/.config/ryoku/current-wallpaper"

      # Single wallpaper owner: DMS (Material You into Theme / QML / stock templates).
      ipc="${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc"
      if [[ -x "$ipc" ]]; then
        "$ipc" wallpaper set "$pick" 2>/dev/null || true
      elif command -v dms >/dev/null 2>&1; then
        dms ipc call wallpaper set "$pick" 2>/dev/null || true
      fi

      if command -v matugen >/dev/null 2>&1; then
        matugen image "$pick" || true
      fi

      # Compositor refresh (best-effort; no dual wallpaper managers).
      if [[ "${compositor}" == "hyprland" ]] && command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
      elif command -v niri >/dev/null 2>&1; then
        niri msg action load-config-file >/dev/null 2>&1 || true
      fi

      echo "wallpaper: $pick"
    '';
  };
}
