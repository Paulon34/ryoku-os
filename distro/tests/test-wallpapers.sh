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
grep -Fq 'resolveGalleryRoots' "$ROOT/distro/apps/ryoku-settings/src/WallpaperGalleryModel.cpp" \
  && pass "unified gallery roots" || fail_msg "missing resolveGalleryRoots"
grep -Fq 'QFileSystemWatcher' "$ROOT/distro/apps/ryoku-settings/src/WallpaperGalleryModel.cpp" \
  && pass "gallery filesystem watcher" || fail_msg "missing QFileSystemWatcher"
grep -Fq 'includeInRepository' "$ROOT/distro/apps/ryoku-settings/src/WallpaperGalleryModel.cpp" \
  && pass "include-in-repo API" || fail_msg "missing includeInRepository"
grep -Fq 'refusing to write into Nix store' "$ROOT/distro/apps/ryoku-settings/src/WallpaperGalleryModel.cpp" \
  && pass "store-write ban" || fail_msg "must refuse Nix store writes"
grep -Fq 'Git e atualizações' "$ROOT/distro/apps/ryoku-settings/qml/pages/NixUpdatesPage.qml" \
  && pass "Git e atualizações title" || fail_msg "NixUpdatesPage not renamed"
grep -Fq 'Repo & branch' "$ROOT/distro/apps/ryoku-settings/qml/pages/NixUpdatesPage.qml" \
  && pass "Repo & branch section" || fail_msg "missing Repo & branch"
grep -Fq 'Nix deps — Advanced' "$ROOT/distro/apps/ryoku-settings/qml/pages/NixUpdatesPage.qml" \
  && pass "Nix advanced section" || fail_msg "missing Nix deps Advanced"
grep -Fq 'Refresh gallery' "$ROOT/distro/apps/ryoku-settings/qml/pages/AppearancePage.qml" \
  && pass "gallery refresh UI" || fail_msg "Appearance missing Refresh gallery"
grep -Fq 'Include in repository' "$ROOT/distro/apps/ryoku-settings/qml/pages/AppearancePage.qml" \
  && pass "include-in-repo UI" || fail_msg "Appearance missing include-in-repo"
# Import helper allows spaces; never auto-git
grep -Fq 'wallpapers-private' "$ROOT/distro/scripts/ryoku-import-wallpaper" \
  && pass "import stays private" || fail_msg "import script path"
! grep -Eq 'git (add|commit|push)' "$ROOT/distro/scripts/ryoku-import-wallpaper" \
  && pass "import never touches git" || fail_msg "import script must not git"

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
grep -Fq 'matugen image "$pick" --mode dark' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "Wallpaper hotkey forces matugen dark mode" || fail_msg "hotkey matugen can flip light"
grep -Fq '"--mode"' "$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp" \
  && pass "Settings wallpaper forces matugen dark mode" || fail_msg "Settings matugen missing --mode dark"

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

# Matugen 4 rejects an empty wallpaper command table; DMS is the renderer.
if grep -Eq "^[[:space:]]*\\[config\\.wallpaper\\]" "$ROOT/distro/flake/home/matugen.nix"; then
  fail_msg "Matugen must not own the wallpaper command"
fi
grep -Fq 'exec nixGLIntel mpvpaper' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "video renderer uses Mesa nixGL" || fail_msg "mpvpaper lacks nixGL wrapper"
grep -Fq 'nixGLIntel = nixGL.packages.' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "HM provides nixGLIntel" || fail_msg "video runtime missing nixGLIntel"

# Live video wallpaper (mpvpaper backend)
[[ -x "$ROOT/distro/scripts/ryoku-video-wallpaper" ]] && pass "ryoku-video-wallpaper exec" \
  || fail_msg "ryoku-video-wallpaper missing/executable"
bash -n "$ROOT/distro/scripts/ryoku-video-wallpaper" && pass "ryoku-video-wallpaper bash -n" \
  || fail_msg "ryoku-video-wallpaper syntax"
grep -Fq 'hwdec=vaapi' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "VA-API preferred decode" || fail_msg "must prefer hwdec=vaapi"
grep -Fq 'gpu-hwdec-interop=vaapi' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "vaapi interop (no NVIDIA wake)" || fail_msg "missing gpu-hwdec-interop=vaapi"
grep -Fq 'matugen image "$poster" --mode dark' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "video poster forces matugen dark" || fail_msg "video matugen missing --mode dark"
grep -Fq './video-wallpaper.nix' "$ROOT/distro/flake/home/home.nix" \
  && pass "home imports video-wallpaper" || fail_msg "home.nix missing video-wallpaper.nix"
grep -Fq 'mpvpaper' "$ROOT/distro/flake/pkgs/ryoku-video-wallpaper.nix" \
  && pass "nix package pulls mpvpaper" || fail_msg "ryoku-video-wallpaper.nix missing mpvpaper"
grep -Fq 'ryoku-video-wallpaper stop' "$ROOT/distro/flake/home/matugen.nix" \
  && pass "change-wallpaper stops video" || fail_msg "hotkey must stop mpvpaper"
grep -Fq 'video-wallpaper.env' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS start resumes video unit" || fail_msg "ryoku-start-dms must start video unit"
grep -Fq '"wallpaperType"' "$ROOT/ryoku/schema/settings.schema.json" \
  && pass "schema wallpaperType" || fail_msg "schema missing wallpaperType"
grep -Fq 'applyVideoWallpaper' "$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp" \
  && pass "Settings applyVideoWallpaper" || fail_msg "WallpaperApplier missing video apply"

# systemd: no After=default.target + WantedBy=default.target cycle on the service
VW="$ROOT/distro/flake/home/video-wallpaper.nix"
! grep -Fq 'After = [ "default.target"' "$VW" \
  && pass "video service does not After=default.target" \
  || fail_msg "video service After=default.target cycles with WantedBy"
# Service Install.WantedBy must be absent (path unit owns autostart).
# Restrict to the service attrset only (stop before paths.*).
if awk '
  /systemd\.user\.services\.ryoku-video-wallpaper/ {in_svc=1}
  /systemd\.user\.paths\.ryoku-video-wallpaper/ {in_svc=0}
  in_svc && /Install\.WantedBy[[:space:]]*=/ {found=1}
  END {exit found?0:1}
' "$VW"; then
  fail_msg "video service must not Install.WantedBy (path unit starts it)"
else
  pass "video service has no Install.WantedBy"
fi
# Path unit (not the service) is WantedBy default.target.
awk '
  /systemd\.user\.paths\.ryoku-video-wallpaper/ {in_path=1}
  in_path && /Install\.WantedBy = \[ "default\.target" \]/ {found=1}
  END {exit found?0:1}
' "$VW" \
  && pass "video path unit WantedBy=default.target" \
  || fail_msg "path unit must WantedBy default.target for GDM login"
grep -Fq 'KillMode = "control-group"' "$VW" \
  && pass "KillMode control-group" || fail_msg "missing KillMode control-group"
grep -Fq 'stop-orphans' "$VW" \
  && pass "ExecStop stop-orphans" || fail_msg "missing ExecStop stop-orphans"
grep -Fq 'stop_orphans' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "helper stop_orphans" || fail_msg "helper missing stop_orphans"
grep -Fq 'systemctl --user start "$unit"' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "apply uses start after stop" || fail_msg "apply must stop then start (not only restart)"
grep -Fq 'mpvpaper.marker' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "mpvpaper marker for orphan tracking" || fail_msg "missing mpvpaper.marker"
grep -Fq 'cmd_unload' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "smart unload command" || fail_msg "missing unload"
grep -Fq 'palette_stamp' "$ROOT/distro/scripts/ryoku-video-wallpaper" \
  && pass "palette stamp for no-rematugen reload" || fail_msg "missing palette stamp"
grep -Fq 'ryoku-video-wallpaper-smart' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "smart watch unit" || fail_msg "missing smart watch unit"
grep -Fq 'video-wallpaper.want' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "renderer arm file (.want)" || fail_msg "missing .want arm contract"
grep -Fq 'ryoku-media-cava.patch' "$ROOT/distro/flake/pkgs/dms-shell-ryoku.nix" \
  && pass "CAVA media patch wired" || fail_msg "CAVA patch not applied in dms-shell"
grep -Fq 'ryoku-media-cava-expanded.patch' "$ROOT/distro/flake/pkgs/dms-shell-ryoku.nix" \
  && pass "CAVA expanded player patch wired" || fail_msg "expanded cava patch missing"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (wallpapers)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
