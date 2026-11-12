#!/usr/bin/env bash
# Static checks for public wallpapers, credits, default seed, private import.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0
pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

W="$ROOT/distro/assets/wallpapers"
for f in ryoku-dusk.jpg ryoku-maple.jpg ryoku-mist.jpg ryoku-night.jpg LICENSE CREDITS.md; do
  [[ -f "$W/$f" ]] && pass "wallpaper asset $f" || fail_msg "missing $W/$f"
done

# No absolute machine paths in wallpaper assets / LICENSE
if grep -REn '/home/[a-zA-Z0-9._-]+|/Users/' "$W" >/dev/null 2>&1; then
  fail_msg "wallpaper tree must not embed machine home paths"
else
  pass "no machine home paths in wallpapers/"
fi

# settings default wallpaper id
grep -Fq '"wallpaper": "ryoku-dusk.jpg"' "$ROOT/distro/ryoku/settings.json" \
  && pass "settings default wallpaper dusk" || fail_msg "settings wallpaper default"

# HM first-login seed matches settings
grep -Fq 'ryoku-dusk.jpg' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "matugen seeds dusk" || fail_msg "matugen must seed ryoku-dusk.jpg"
grep -Fq 'wallpapers-private' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "matugen ensures private dir" || fail_msg "matugen missing private dir"
grep -Fq 'ryoku-import-wallpaper' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "HM packages import helper" || fail_msg "missing import wallpaper in HM"

[[ -x "$ROOT/distro/scripts/ryoku-import-wallpaper" ]] && pass "import script exec" \
  || fail_msg "import script not executable"
[[ -x "$ROOT/distro/scripts/make-wallpapers.sh" ]] && pass "make-wallpapers.sh exec" \
  || fail_msg "make-wallpapers.sh missing"

# Gallery model merges private path
grep -Fq 'resolvePrivateGalleryPath' "$ROOT/distro/apps/ryoku-settings/src/WallpaperGalleryModel.cpp" \
  && pass "gallery private merge" || fail_msg "WallpaperGalleryModel missing private merge"
grep -Fq 'wallpapers-private' "$ROOT/distro/apps/ryoku-settings/src/WallpaperGalleryModel.cpp" \
  && pass "private path string" || fail_msg "missing wallpapers-private string"

# Material You regression: wallpaper must change palette, not just background.
# On the first Debian VM boot, DMS used fixed stock Purple (#D0BCFF) and
# matugen ran independently; image selection never changed shell colors.
grep -Fq 'currentThemeName = "dynamic";' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS first-login theme is dynamic" || fail_msg "DMS seeds stock theme"
grep -Fq 'defaultWallpaper = "${config.home.homeDirectory}/.local/share/wallpapers/ryoku-dusk.jpg"' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS first wallpaper matches Ryoku default" || fail_msg "DMS default differs from Ryoku wallpaper"
grep -Fq '.currentThemeName = "dynamic"' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS HM activation migrates stock theme" || fail_msg "DMS does not migrate existing settings"
grep -Fq 'appearance.dynamicColors == false' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS respects user dynamicColors off" || fail_msg "DMS ignores saved Dynamic Colors switch"
grep -Fq 'runUserMatugenTemplates = true' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS runs custom Matugen templates" || fail_msg "DMS Matugen templates disabled"
grep -Fq 'applyWallpaperWithTheme(fileName, root.draftDynamicColors)' "$ROOT/distro/apps/ryoku-settings/qml/pages/AppearancePage.qml" \
  && pass "Settings passes live Dynamic Colors preference" || fail_msg "Settings applies wallpaper without theme preference"
grep -Fq 'wallpaperApplier.setDynamicColors(draftDynamicColors)' "$ROOT/distro/apps/ryoku-settings/qml/pages/AppearancePage.qml" \
  && pass "Settings Save synchronizes DMS theme" || fail_msg "Settings Save does not refresh dynamic mode"
grep -Fq 'settings"), QStringLiteral("set")' "$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp" \
  && pass "Settings changes DMS theme via IPC" || fail_msg "Settings does not sync DMS theme over IPC"
grep -Fq 'mg.exitCode() != 0' "$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp" \
  && pass "Matugen failures are checked" || fail_msg "Matugen failure silently ignored"

grep -Fq 'settings set currentThemeName dynamic' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "Wallpaper hotkey selects dynamic DMS mode" || fail_msg "hotkey wallpaper never enables dynamic DMS"
grep -Fq 'if [[ "$dynamic" == true ]]; then' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "Wallpaper hotkey respects disabled Dynamic Colors" || fail_msg "hotkey ignores color preference"
grep -Fq 'WARN: matugen image failed' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "Wallpaper hotkey reports Matugen failure" || fail_msg "hotkey hides Matugen errors"

# DMS single-instance flock (Hyprland exec-once reuse)
grep -Fq 'flock' "$ROOT/distro/flake/home/dms.nix" \
  && pass "dms start flock" || fail_msg "ryoku-start-dms missing flock"

# Guest regression: DMS starts when dispatched manually but first GUI login
# showed a black screen. Persist startup diagnostics and ensure an async
# bar-settings worker cannot keep fd9 locked after an early DMS failure.
grep -Fq 'dms-startup.log' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS login diagnostics persisted" || fail_msg "DMS startup log missing"
grep -Fq ') 9>&- &' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS child closes inherited flock" || fail_msg "async DMS worker inherits fd9"
grep -Fq 'for attempt in 1 2; do' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS early-exit retry is bounded" || fail_msg "bounded DMS recovery missing"
grep -Fq 'missing Wayland socket' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS startup waits for Wayland" || fail_msg "DMS missing Wayland readiness guard"
grep -Fq 'ryoku-start-dms' "$ROOT/distro/flake/home/hyprland.nix" \
  && pass "hyprland exec-once dms" || fail_msg "hyprland missing dms exec-once"
# Exactly one exec-once for dms in hyprland.nix
count=$(grep -c 'ryoku-start-dms' "$ROOT/distro/flake/home/hyprland.nix" || true)
[[ "$count" -eq 1 ]] && pass "single hyprland dms reference" || fail_msg "expected 1 dms ref in hyprland.nix (got $count)"

# No hyprpaper/swww competing wallpaper managers in hyprland conf
if grep -Eiq 'hyprpaper|swww' "$ROOT/distro/flake/home/hyprland.nix"; then
  fail_msg "hyprland must not enable competing wallpaper managers"
else
  pass "no hyprpaper/swww in hyprland.nix"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (wallpapers)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
