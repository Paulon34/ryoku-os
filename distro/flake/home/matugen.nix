{ config, pkgs, lib, ... }:

# Material You via Matugen — wallpaper-driven palette for Niri/kitty/fuzzel.
# Ported from ryoku-desktop home/theme.nix + matugen templates; Hyprland
# templates replaced by ryoku-niri-colors.kdl.
#
# Theme engine (parity with desktop scripts/change-wallpaper.sh):
#   1) `dms ipc call wallpaper set` → DMS regenerates Theme + runs matugen
#      (including stock niri → ~/.config/niri/dms/colors.kdl + user templates).
#   2) Optional user `matugen image` keeps palette.json/css + colors.kdl fallback
#      when DMS IPC is down; never invents a second wallpaper owner.
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

  # Stock DMS matugen/templates/niri-colors.kdl shape (neutral seed).
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
  '';

  home.file.".config/matugen/templates/ryoku-palette.json".source = ./matugen/templates/ryoku-palette.json;
  home.file.".config/matugen/templates/ryoku-palette.css".source = ./matugen/templates/ryoku-palette.css;
  home.file.".config/matugen/templates/ryoku-niri-colors.kdl".source = ./matugen/templates/ryoku-niri-colors.kdl;

  # Niri `include optional=true` tolerates missing files, but guests still need
  # real seeds before the first wallpaper apply. Never overwrite Matugen/DMS writes.
  home.activation.ensureRyokuNiriColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/niri/dms" "$HOME/.config/ryoku"
    if [ ! -e "$HOME/.config/niri/colors.kdl" ]; then
      run install -m 644 ${niriColorsFallback} "$HOME/.config/niri/colors.kdl"
    fi
    if [ ! -e "$HOME/.config/niri/dms/colors.kdl" ]; then
      run install -m 644 ${dmsNiriColorsFallback} "$HOME/.config/niri/dms/colors.kdl"
    fi
    wallpaper="$HOME/.local/share/wallpapers/ryoku-night.jpg"
    if [ -f "$wallpaper" ] && [ ! -e "$HOME/.config/ryoku/current-wallpaper" ]; then
      run ln -sfn "$wallpaper" "$HOME/.config/ryoku/current-wallpaper"
    fi
  '';

  # Match ryoku-desktop/scripts/change-wallpaper.sh: DMS owns live wallpaper +
  # Material You into shell components; user matugen templates follow for Niri
  # fallback / palette files when the CLI is available.
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

      ipc="${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc"
      if [[ -x "$ipc" ]]; then
        "$ipc" wallpaper set "$pick" 2>/dev/null || true
      elif command -v dms >/dev/null 2>&1; then
        dms ipc call wallpaper set "$pick" 2>/dev/null || true
      fi

      # User templates (palette + colors.kdl). DMS already ran matugen for Theme
      # + dms/colors.kdl when IPC succeeded; this keeps Niri fallback fresh if not.
      if command -v matugen >/dev/null 2>&1; then
        matugen image "$pick" || true
      fi

      if command -v niri >/dev/null 2>&1; then
        niri msg action load-config-file >/dev/null 2>&1 || true
      fi

      echo "wallpaper: $pick"
    '';
  };
}
