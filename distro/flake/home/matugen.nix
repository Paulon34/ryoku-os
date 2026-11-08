{ config, pkgs, lib, ... }:

# Material You via Matugen — wallpaper-driven palette for Niri/kitty/fuzzel.
# Ported from ryoku-desktop home/theme.nix + matugen templates; Hyprland
# templates replaced by ryoku-niri-colors.kdl.
let
  niriColorsFallback = pkgs.writeText "ryoku-niri-colors-fallback.kdl" ''
    // Ryoku Appearance Engine — Niri focus-ring fallback (pre-Matugen).
    // Replaced when change-wallpaper / matugen runs against a wallpaper.
    layout {
        focus-ring {
            width 2
            active-color "#8a9099"
            inactive-color "#3a3a3a"
        }
    }
  '';
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
  '';

  home.file.".config/matugen/templates/ryoku-palette.json".source = ./matugen/templates/ryoku-palette.json;
  home.file.".config/matugen/templates/ryoku-palette.css".source = ./matugen/templates/ryoku-palette.css;
  home.file.".config/matugen/templates/ryoku-niri-colors.kdl".source = ./matugen/templates/ryoku-niri-colors.kdl;

  # Niri `include optional=true "colors.kdl"` tolerates a missing file, but
  # guests still need a real Matugen output after the first wallpaper apply.
  # Seed a neutral fallback once; never overwrite Matugen's later writes.
  home.activation.ensureRyokuNiriColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/niri" "$HOME/.config/ryoku"
    if [ ! -e "$HOME/.config/niri/colors.kdl" ]; then
      run install -m 644 ${niriColorsFallback} "$HOME/.config/niri/colors.kdl"
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
      mkdir -p "${config.home.homeDirectory}/.config/ryoku" "${config.home.homeDirectory}/.config/niri"
      ln -sfn "$pick" "${config.home.homeDirectory}/.config/ryoku/current-wallpaper"
      if command -v matugen >/dev/null 2>&1; then
        matugen image "$pick" || true
      fi
      ipc="${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc"
      if [[ -x "$ipc" ]]; then
        "$ipc" wallpaper set "$pick" 2>/dev/null || true
      elif command -v dms >/dev/null 2>&1; then
        dms ipc call wallpaper set "$pick" 2>/dev/null || true
      fi
      echo "wallpaper: $pick"
    '';
  };
}
