#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
for s in ryoku-printers ryoku-import-personal ryoku-workstation-tools; do
  bash -n "$ROOT/distro/scripts/$s"
done
for pkg in cups cups-filters hplip printer-driver-hpcups printer-driver-gutenprint cups-client avahi-daemon libcups2t64; do
  grep -Fxq "$pkg" "$ROOT/distro/apt/packages-full.txt"
done
grep -Fq 'rastertosnailtspl-4barcode' "$ROOT/distro/scripts/ryoku-printers"
grep -Fq 'cupstestppd' "$ROOT/distro/scripts/ryoku-printers"
grep -Fq 'not found' "$ROOT/distro/scripts/ryoku-printers"
grep -Fq 'pending-imported-wallpaper' "$ROOT/distro/scripts/ryoku-import-personal"
grep -Fq 'pending-imported-wallpaper' "$ROOT/distro/flake/home/dms.nix"
grep -Fq 'Private images deliberately live outside the pure Nix source' "$ROOT/distro/ryoku/lib.nix"
# The import runs against a disposable repo and home, never the test runner's
# personal files. It only copies allowed images and the selected basenames.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/distro/scripts" "$tmp/repo/ryoku" "$tmp/private/assets/wallpapers" "$tmp/private/ryoku" "$tmp/home"
cp "$ROOT/distro/scripts/ryoku-import-personal" "$tmp/repo/distro/scripts/"
printf '{"appearance":{"shellStyle":"quattro"},"schemaVersion":1}\n' > "$tmp/repo/ryoku/settings.json"
printf '{"appearance":{"wallpaper":"sample.jpg","loginWallpaper":"sample.jpg"},"private":"do not import"}\n' > "$tmp/private/ryoku/settings.json"
printf 'fixture\n' > "$tmp/private/assets/wallpapers/sample.jpg"
printf 'excluded\n' > "$tmp/private/assets/wallpapers/secret.txt"
if [[ $EUID != 0 ]]; then
  HOME="$tmp/home" bash "$tmp/repo/distro/scripts/ryoku-import-personal" "$tmp/private"
  test -f "$tmp/home/.local/share/ryoku/wallpapers-private/sample.jpg"
  test ! -e "$tmp/home/.local/share/ryoku/wallpapers-private/secret.txt"
  grep -Fxq sample.jpg "$tmp/home/.config/ryoku/pending-imported-wallpaper"
  python3 - "$tmp/repo/ryoku/settings.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d["appearance"]["shellStyle"]=="quattro"
assert d["appearance"]["wallpaper"]=="sample.jpg"
assert d["appearance"]["loginWallpaper"]=="sample.jpg"
assert "private" not in d
PY
fi
echo "PASS_STATIC: migration asset routing and printer setup (no actual device test)"
