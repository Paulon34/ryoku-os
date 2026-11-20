#!/usr/bin/env bash
# Generates the wallpapers shipped with the public Ryoku edition.
#
# They are original, procedural images (gradients + seeded plasma noise), so
# their provenance is this script: re-running it with the same ImageMagick
# reproduces them. Licensed CC0-1.0 (assets/wallpapers/LICENSE in the public edition).
#
#   nix shell nixpkgs#imagemagick -c scripts/make-wallpapers.sh <out-dir>

set -euo pipefail

out=${1:?usage: make-wallpapers.sh OUT_DIR}
mkdir -p "$out"
W=2560 H=1440

# name  seed  gradient-from  gradient-to  tint
make() {
  local name=$1 seed=$2 from=$3 to=$4 tint=$5
  magick -size "${W}x${H}" -seed "$seed" plasma:"$from-$to" \
    -blur 0x48 -modulate 100,70 \
    \( -size "${W}x${H}" gradient:"$from-$to" -rotate 0 \) -compose softlight -composite \
    \( -size "${W}x${H}" radial-gradient:"none-#000000aa" \) -compose over -composite \
    -fill "$tint" -colorize 12% \
    -strip -interlace JPEG -sampling-factor 4:2:0 -quality 86 "$out/$name.jpg"
  echo "$out/$name.jpg"
}

make ryoku-dusk 1101 "#1b1430" "#c9733d" "#3a2a52"
make ryoku-maple 2203 "#2a0d0d" "#d2452f" "#5a1e14"
make ryoku-mist 3307 "#0f1b22" "#7fa7a0" "#20343a"
make ryoku-night 4409 "#07090f" "#3b4a7a" "#111a33"
