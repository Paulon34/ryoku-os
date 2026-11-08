{ config, pkgs, lib, ... }:

# Material You via Matugen — wallpaper-driven palette for Niri/kitty/fuzzel.
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

  home.file.".local/bin/change-wallpaper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      WALL_DIR="${config.home.homeDirectory}/.local/share/wallpapers"
      mapfile -t walls < <(find "$WALL_DIR" -type f \( -name '*.jpg' -o -name '*.png' \) | sort)
      [[ ''${#walls[@]} -gt 0 ]] || { echo "no wallpapers in $WALL_DIR" >&2; exit 1; }
      pick=''${walls[RANDOM % ''${#walls[@]}]}
      mkdir -p "${config.home.homeDirectory}/.config/ryoku"
      ln -sfn "$pick" "${config.home.homeDirectory}/.config/ryoku/current-wallpaper"
      if command -v matugen >/dev/null 2>&1; then
        matugen image "$pick" || true
      fi
      # Hint DMS to reload wallpaper if running.
      if command -v dms >/dev/null 2>&1; then
        dms ipc call wallpaper set "$pick" 2>/dev/null || true
      fi
      echo "wallpaper: $pick"
    '';
  };
}
