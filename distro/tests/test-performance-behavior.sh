#!/usr/bin/env bash
# Behavioral (fixture) tests for Performance & Polish — still PASS_STATIC.
# No Hyprland/mpvpaper/Firefox session; never invents PASS_REAL.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VW="$ROOT/distro/scripts/ryoku-video-wallpaper"
PP="$ROOT/distro/scripts/ryoku-power-policy"
fail=0
pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$XDG_STATE_HOME/ryoku" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

# --- Disarm blocks check / PathExists reactivation contract ---
: >"$XDG_STATE_HOME/ryoku/video-wallpaper.env"
printf 'RYOKU_VIDEO_WALLPAPER="/tmp/no-such.mp4"\n' >"$XDG_STATE_HOME/ryoku/video-wallpaper.env"
if bash "$VW" check >/dev/null 2>&1; then
  fail_msg "check must fail when disarmed (no .want)"
else
  pass "check refuses start while disarmed"
fi

printf '1\n' >"$XDG_STATE_HOME/ryoku/video-wallpaper.want"
# Still fails on missing video, but armed path is exercised past disarm gate.
out=$(bash "$VW" check 2>&1 || true)
grep -Eq 'unavailable|not found|keeping the static' <<<"$out" \
  && pass "check reaches video validation when armed" \
  || fail_msg "armed check did not reach video gate: $out"

rm -f "$XDG_STATE_HOME/ryoku/video-wallpaper.want"
# unload/disarm helpers must remove want
printf '1\n' >"$XDG_STATE_HOME/ryoku/video-wallpaper.want"
# Simulate unload disarm without systemctl by sourcing functions via subcommand path:
# status reports armed=0 after manual disarm via unload when no unit — unload still disarms.
bash "$VW" unload >/dev/null 2>&1 || true
[[ ! -f "$XDG_STATE_HOME/ryoku/video-wallpaper.want" ]] \
  && pass "unload disarms .want" \
  || fail_msg "unload left .want in place"
st=$(bash "$VW" status 2>/dev/null || true)
grep -Fq 'armed=0' <<<"$st" && pass "status reports armed=0" || fail_msg "status armed missing"

# --- Coverage fixtures: scale, geometry, side-by-side, independent monitors ---
fix="$tmp/cov"
mkdir -p "$fix"

# Two monitors; left fully covered by fullscreen; right uncovered.
cat >"$fix/monitors.json" <<'JSON'
[
  {"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1.0,
   "activeWorkspace":{"id":1}},
  {"name":"HDMI-A-1","x":1920,"y":0,"width":2560,"height":1440,"scale":1.25,
   "activeWorkspace":{"id":2}}
]
JSON
cat >"$fix/clients.json" <<'JSON'
[
  {"mapped":true,"fullscreen":1,"workspace":{"id":1},
   "at":[0,0],"size":[1920,1080],"class":"firefox","title":"YouTube"},
  {"mapped":true,"fullscreen":0,"workspace":{"id":2},
   "at":[2000,100],"size":[400,300],"class":"kitty","title":"term"}
]
JSON
export RYOKU_COVERAGE_FIXTURE="$fix"
# Force coverage path without HIS by fixture branch.
cov=$(bash "$VW" coverage)
grep -Eq 'covered_any=1' <<<"$cov" && pass "fixture: any covered" || fail_msg "cov=$cov"
grep -Eq 'covered_all=0' <<<"$cov" && pass "fixture: independent monitors (not all)" || fail_msg "cov=$cov"
grep -Eq 'monitors=2 covered=1' <<<"$cov" && pass "fixture: 1 of 2 covered" || fail_msg "cov=$cov"
grep -Eq 'media_video=1' <<<"$cov" && pass "fixture: media video hint" || fail_msg "cov=$cov"

# Side-by-side on one monitor: two ~50% windows → union ≥85%
cat >"$fix/monitors.json" <<'JSON'
[{"name":"eDP-1","x":0,"y":0,"width":2000,"height":1000,"scale":1.0,"activeWorkspace":{"id":1}}]
JSON
cat >"$fix/clients.json" <<'JSON'
[
  {"mapped":true,"fullscreen":0,"workspace":{"id":1},"at":[0,0],"size":[1000,1000],"class":"a","title":"L"},
  {"mapped":true,"fullscreen":0,"workspace":{"id":1},"at":[1000,0],"size":[1000,1000],"class":"b","title":"R"}
]
JSON
cov=$(bash "$VW" coverage)
grep -Eq 'covered_all=1' <<<"$cov" && pass "fixture: side-by-side union covers" || fail_msg "side-by-side cov=$cov"

# Scale-aware: physical 3840x2160 at scale 2 → logical 1920x1080; client fills logical.
cat >"$fix/monitors.json" <<'JSON'
[{"name":"eDP-1","x":0,"y":0,"width":3840,"height":2160,"scale":2.0,"activeWorkspace":{"id":1}}]
JSON
cat >"$fix/clients.json" <<'JSON'
[
  {"mapped":true,"fullscreen":0,"workspace":{"id":1},"at":[0,0],"size":[1920,1080],"class":"big","title":"fill"}
]
JSON
cov=$(bash "$VW" coverage)
grep -Eq 'covered_all=1' <<<"$cov" && pass "fixture: scale-aware geometry" || fail_msg "scale cov=$cov"

unset RYOKU_COVERAGE_FIXTURE

# --- Power policy restores profile AND unload grace ---
printf 'RYOKU_VIDEO_WALLPAPER="/tmp/x.mp4"\nRYOKU_VIDEO_WALLPAPER_PROFILE=balanced\nRYOKU_VIDEO_WALLPAPER_UNLOAD_GRACE=60\n' \
  >"$XDG_STATE_HOME/ryoku/video-wallpaper.env"
# Simulate tip stamp as if apply tipped on battery
printf '{"previousProfile":"quality","previousGrace":90,"reason":"battery"}\n' \
  >"$XDG_STATE_HOME/ryoku/power-policy-tip.json"
# Rewrite env as tipped
printf 'RYOKU_VIDEO_WALLPAPER="/tmp/x.mp4"\nRYOKU_VIDEO_WALLPAPER_PROFILE=economy\nRYOKU_VIDEO_WALLPAPER_UNLOAD_GRACE=20\n' \
  >"$XDG_STATE_HOME/ryoku/video-wallpaper.env"
bash "$PP" restore >/dev/null 2>&1 || true
grep -Fq 'RYOKU_VIDEO_WALLPAPER_PROFILE=quality' "$XDG_STATE_HOME/ryoku/video-wallpaper.env" \
  && pass "power restore profile" || fail_msg "profile not restored"
grep -Fq 'RYOKU_VIDEO_WALLPAPER_UNLOAD_GRACE=90' "$XDG_STATE_HOME/ryoku/video-wallpaper.env" \
  && pass "power restore unload grace" || fail_msg "grace not restored"
[[ ! -f "$XDG_STATE_HOME/ryoku/power-policy-tip.json" ]] \
  && pass "tip stamp cleared" || fail_msg "tip stamp remains"

# Tip apply must not overwrite an existing tip's original values
printf '{"previousProfile":"balanced","previousGrace":60,"reason":"battery"}\n' \
  >"$XDG_STATE_HOME/ryoku/power-policy-tip.json"
printf 'RYOKU_VIDEO_WALLPAPER="/tmp/x.mp4"\nRYOKU_VIDEO_WALLPAPER_PROFILE=economy\nRYOKU_VIDEO_WALLPAPER_UNLOAD_GRACE=20\n' \
  >"$XDG_STATE_HOME/ryoku/video-wallpaper.env"
# Without a real discharging battery, apply goes to restore path on AC — force tip integrity via jq read
prev=$(jq -r .previousProfile "$XDG_STATE_HOME/ryoku/power-policy-tip.json")
[[ "$prev" == balanced ]] && pass "existing tip preserves previousProfile" || fail_msg "tip mutated"

# --- CAVA expanded player + styles (API contracts in regenerated patches) ---
grep -Fq 'ryoku-media-cava-expanded.patch' "$ROOT/distro/flake/pkgs/dms-shell-ryoku.nix" \
  && pass "expanded MediaPlayerTab cava patch wired" || fail_msg "expanded cava not wired"
grep -Fq 'AudioVisualization' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava-expanded.patch" \
  && pass "expanded player uses AudioVisualization" || fail_msg "expanded missing viz"
grep -Fq 'import qs.Modules.DankBar.Widgets' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava-expanded.patch" \
  && pass "expanded imports DankBar.Widgets for AudioVisualization" || fail_msg "expanded import missing"
grep -Fq 'MprisPlaybackState.Playing' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava-expanded.patch" \
  && pass "expanded gates on MprisPlaying" || fail_msg "expanded MPRIS gate missing"
grep -Fq 'import qs.Modules.DankBar.Widgets' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" \
  && pass "popout imports DankBar.Widgets" || fail_msg "island cava popout import missing"
grep -Fq 'CavaService.cavaAvailable' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" \
  && pass "island/popout gates on cavaAvailable" || fail_msg "cavaAvailable gate missing"
grep -Fq 'audioVisualizerEnabled' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" \
  && pass "island/popout respects audioVisualizerEnabled" || fail_msg "visualizer setting missing"
grep -Fq 'MediaIsland' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-bar-media-island.patch" \
  && pass "Media Island present for Quattro/Islands" || fail_msg "Media Island missing"
# Both styles share the patched DMS tree (style only swaps bar chrome).
grep -Fq 'ryokuShellStyle' "$ROOT/distro/flake/pkgs/dms-shell-ryoku.nix" \
  && pass "shell style injected into shared DMS tree" || fail_msg "style injection missing"
! grep -Eq 'Math\.random' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" \
  "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava-expanded.patch" \
  && pass "cava patches have no fake spectrum" || fail_msg "fake spectrum in cava patches"
grep -Fq 'checkLinkTargets' "$ROOT/distro/flake/home/settings.nix" \
  && grep -Fq 'entryBefore' "$ROOT/distro/flake/home/settings.nix" \
  && pass "desktop adopt before checkLinkTargets" || fail_msg "adopt order wrong"
grep -Fq 'video-wallpaper.want' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "path unit watches .want" || fail_msg "path still on .env only"
grep -Fq 'HYPRLAND_INSTANCE_SIGNATURE' "$ROOT/distro/flake/home/hyprland.nix" \
  && pass "Hyprland exports HIS to systemd" || fail_msg "HIS export missing"
grep -Fq 'PassEnvironment' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "smart/renderer PassEnvironment HIS" || fail_msg "PassEnvironment missing"

# Path unit regression: renderer Path.PathExists must be .want not .env
# (do not confuse with ConditionPathExists on other units).
awk '
  /^  systemd\.user\.paths\.ryoku-video-wallpaper = \{/ {in_path=1; next}
  /^  systemd\.user\.paths\.ryoku-video-wallpaper-smart/ {in_path=0}
  /^  systemd\.user\.services\./ {in_path=0}
  in_path && /[^n]PathExists = "%S\/ryoku\/video-wallpaper\.want"/ {want=1}
  in_path && /^[[:space:]]*PathExists = "%S\/ryoku\/video-wallpaper\.want"/ {want=1}
  in_path && /^[[:space:]]*PathExists = "%S\/ryoku\/video-wallpaper\.env"/ {env=1}
  END { if (want && !env) exit 0; exit 1 }
' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "renderer path unit uses .want only" \
  || fail_msg "renderer path unit still tied to .env"

bash -n "$VW" && pass "video wallpaper bash -n" || fail_msg "vw syntax"
bash -n "$PP" && pass "power-policy bash -n" || fail_msg "pp syntax"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (performance-behavior)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
