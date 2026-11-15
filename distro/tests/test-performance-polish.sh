#!/usr/bin/env bash
# Static regressions for Performance & Polish (launcher, smart wallpaper, CAVA, power).
# Never claims PASS_REAL — cloud has no Hyprland/mpvpaper/Firefox session.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0
pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

# --- Launcher ---
grep -Fq 'ryoku-settings-launcher-check' "$ROOT/distro/flake/home/settings.nix" \
  && pass "launcher-check helper packaged" || fail_msg "missing launcher-check"
grep -Fq 'ryokuSettingsDesktopAdopt' "$ROOT/distro/flake/home/settings.nix" \
  && pass "desktop adopt/backup activation" || fail_msg "missing desktop adopt"
grep -Fq 'X-Ryoku-Managed' "$ROOT/distro/flake/home/settings.nix" \
  && pass "managed desktop marker" || fail_msg "missing X-Ryoku-Managed"
grep -Fq 'Keywords[pt_BR]' "$ROOT/distro/flake/home/settings.nix" \
  && pass "pt_BR Keywords" || fail_msg "missing Keywords[pt_BR]"
grep -Fq 'desktop-backup' "$ROOT/distro/flake/home/settings.nix" \
  && pass "manual desktop backup dir" || fail_msg "missing desktop-backup"

# --- Smart wallpaper ---
VW="$ROOT/distro/scripts/ryoku-video-wallpaper"
bash -n "$VW" && pass "video wallpaper bash -n" || fail_msg "video wallpaper syntax"
for cmd in coverage pause unpause unload reload watch; do
  grep -Eq "^  $cmd\\)" "$VW" \
    && pass "subcommand $cmd" || fail_msg "missing subcommand $cmd"
done
grep -Fq 'palette_stamp' "$VW" && pass "palette stamp (no rematugen on reload)" \
  || fail_msg "missing palette stamp"
grep -Fq 'cmd_reload' "$VW" && grep -Fq 'Do NOT call matugen' "$VW" \
  && pass "reload skips matugen" || fail_msg "reload must skip matugen"
if grep -Fq 'kill -STOP' "$VW"; then
  pass "soft pause via SIGSTOP"
else
  fail_msg "missing SIGSTOP pause"
fi
grep -Fq 'ryoku-video-wallpaper-smart' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "smart systemd unit" || fail_msg "missing smart unit"
grep -Fq 'smartUnload' "$ROOT/ryoku/schema/settings.schema.json" \
  && pass "schema smartUnload" || fail_msg "schema missing smartUnload"
grep -Fq 'mediaPausePolicy' "$ROOT/ryoku/schema/settings.schema.json" \
  && pass "schema mediaPausePolicy" || fail_msg "schema missing mediaPausePolicy"
grep -Fq 'unloadGraceSec' "$ROOT/distro/ryoku/schema/settings.schema.json" \
  && pass "distro schema unloadGraceSec" || fail_msg "distro schema missing unloadGraceSec"

# Smart service must not WantedBy default.target on the service itself.
if awk '
  /systemd\.user\.services\.ryoku-video-wallpaper-smart/ {in_svc=1}
  /systemd\.user\.paths\.ryoku-video-wallpaper-smart/ {in_svc=0}
  /systemd\.user\.services\.ryoku-power-policy/ {in_svc=0}
  in_svc && /Install\.WantedBy[[:space:]]*=/ {found=1}
  END {exit found?0:1}
' "$ROOT/distro/flake/home/video-wallpaper.nix"; then
  fail_msg "smart service must not Install.WantedBy"
else
  pass "smart service has no Install.WantedBy"
fi

# --- CAVA ---
grep -Fxq cava "$ROOT/distro/apt/packages-base.txt" \
  && pass "APT cava" || fail_msg "packages-base missing cava"
grep -Fxq socat "$ROOT/distro/apt/packages-base.txt" \
  && pass "APT socat" || fail_msg "packages-base missing socat"
[[ -f "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" ]] \
  && pass "media cava patch present" || fail_msg "missing ryoku-media-cava.patch"
grep -Fq 'ryoku-media-cava.patch' "$ROOT/distro/flake/pkgs/dms-shell-ryoku.nix" \
  && pass "dms-shell applies cava patch" || fail_msg "dms-shell missing cava patch"
grep -Fq 'AudioVisualization' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" \
  && pass "Media Island uses AudioVisualization" || fail_msg "patch missing AudioVisualization"
grep -Fq 'audioVisualizerEnabled = true' "$ROOT/distro/flake/home/dms.nix" \
  && pass "DMS audioVisualizerEnabled" || fail_msg "DMS must enable visualizer"
# No fake Math.random spectrum in our patch
! grep -Fq 'Math.random' "$ROOT/distro/flake/patches/dms/1.5.3/ryoku-media-cava.patch" \
  && pass "cava patch has no fake spectrum" || fail_msg "cava patch must not invent spectrum"

# --- Dual monitor / Hyprland ---
grep -Fq 'vfr = true' "$ROOT/distro/flake/home/hyprland.nix" \
  && pass "Hyprland vfr" || fail_msg "missing vfr"
grep -Fq 'Dual-monitor' "$ROOT/distro/flake/home/hyprland.nix" \
  && pass "dual-monitor comments" || fail_msg "missing dual-monitor notes"
grep -Fq 'passes = 2' "$ROOT/distro/flake/home/hyprland.nix" \
  && pass "blur passes capped" || fail_msg "blur passes"

# --- GPU sensors honesty ---
grep -Fq 'Intel iGPU' "$ROOT/distro/scripts/ryoku-hardware" \
  && pass "Intel iGPU sysfs sensors" || fail_msg "missing Intel iGPU sensors"
grep -Fq 'utilization%% not claimed' "$ROOT/distro/scripts/ryoku-hardware" \
  && pass "Intel util% not invented" || fail_msg "must not invent Intel util%"
grep -Fq 'asleep' "$ROOT/distro/scripts/ryoku-hardware" \
  && pass "NVIDIA asleep/unavailable wording" || fail_msg "NVIDIA honesty wording"

# Fixture: Intel drm card without inventing util%
tmp=$(mktemp -d)
mkdir -p "$tmp/sys/class/drm/card0/device" "$tmp/proc" "$tmp/sys/class/hwmon" \
  "$tmp/sys/class/thermal" "$tmp/sys/class/power_supply" "$tmp/sys/bus/pci/devices" \
  "$tmp/sys/bus/usb/devices"
printf 'cpu  0 0 0 100 0 0 0 0 0 0\n' >"$tmp/proc/stat"
printf 'MemTotal: 8000000 kB\nMemAvailable: 4000000 kB\n' >"$tmp/proc/meminfo"
printf 'vendor_id : GenuineIntel\n' >"$tmp/proc/cpuinfo"
printf '0x8086\n' >"$tmp/sys/class/drm/card0/device/vendor"
printf '300\n' >"$tmp/sys/class/drm/card0/device/gt_cur_freq_mhz"
printf '280\n' >"$tmp/sys/class/drm/card0/device/gt_act_freq_mhz"
sensors=$(bash "$ROOT/distro/scripts/ryoku-hardware" --sysroot "$tmp" --sensors)
grep -Fq 'gt_cur_freq_mhz=300' <<<"$sensors" \
  && pass "Intel freq from fixture" || fail_msg "Intel fixture freq missing"
! grep -Eqi 'util.*=.*[0-9]+%' <<<"$sensors" \
  && pass "fixture invents no util%" || fail_msg "sensors invented util%"
rm -rf "$tmp"

# --- Power policy ---
[[ -x "$ROOT/distro/scripts/ryoku-power-policy" ]] \
  && pass "power-policy executable" || fail_msg "power-policy missing/exec"
bash -n "$ROOT/distro/scripts/ryoku-power-policy" \
  && pass "power-policy bash -n" || fail_msg "power-policy syntax"
grep -Fq 'ryoku-power-policy' "$ROOT/distro/flake/home/video-wallpaper.nix" \
  && pass "HM wires power-policy" || fail_msg "HM missing power-policy"

# --- Docs ---
grep -Fq 'smartUnload' "$ROOT/distro/docs/VIDEO_WALLPAPER.md" \
  || grep -Fq 'Unload' "$ROOT/distro/docs/VIDEO_WALLPAPER.md" \
  && pass "VIDEO_WALLPAPER documents unload" || fail_msg "VIDEO_WALLPAPER missing unload"
grep -Fq 'media.ffmpeg.vaapi.enabled' "$ROOT/distro/docs/FIREFOX_MEDIA.md" \
  && pass "FIREFOX_MEDIA safe prefs" || fail_msg "FIREFOX_MEDIA incomplete"
grep -Fq 'PASS_STATIC' "$ROOT/distro/docs/PERFORMANCE_POLISH.md" \
  && pass "PERFORMANCE_POLISH status section" || fail_msg "PERFORMANCE_POLISH status"

# --- SettingsStore keys ---
grep -Fq 'smartUnload' "$ROOT/distro/apps/ryoku-settings/src/SettingsStore.cpp" \
  && pass "SettingsStore smartUnload" || fail_msg "SettingsStore missing smartUnload"
grep -Fq 'mediaPausePolicy' "$ROOT/distro/apps/ryoku-settings/src/SettingsStore.cpp" \
  && pass "SettingsStore mediaPausePolicy" || fail_msg "SettingsStore missing mediaPausePolicy"

# Coverage without Hyprland must degrade safely
out=$(bash "$VW" coverage)
grep -Eq 'covered_all=0' <<<"$out" \
  && pass "coverage degrades without Hyprland" || fail_msg "coverage unsafe without compositor: $out"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (performance-polish)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
