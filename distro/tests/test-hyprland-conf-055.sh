#!/usr/bin/env bash
# Static guard: Hyprland conf must target Debian ~0.55.x, not NixOS 0.56.2.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HYPR="$ROOT/distro/flake/home/hyprland.nix"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$HYPR" ]] || fail "hyprland.nix missing"

# Ban 0.56-style keys in emitted conf lines (ignore # comments).
code_lines() { grep -vE '^\s*#' "$HYPR" || true; }
code_lines | grep -Eq 'windowrule[[:space:]]*=[[:space:]]*(float|center|size[[:space:]][0-9]+[[:space:]][0-9]+),[[:space:]]*(class|title):' &&
  fail "obsolete windowrule = float, class:… is invalid in Hyprland 0.55.x"
code_lines | grep -Fq 'new_optimizations' &&
  fail "blur:new_optimizations removed/unsafe for 0.55 target — omit it"
code_lines | grep -Fq 'no_anim on, match:namespace' &&
  fail "0.56 layerrule form banned; use classic layerrule = noanim, …"
# Hyprland 0.55.2 still reads legacy Hyprlang configs but requires
# 0.53+ window rules: match:class/title matchers and effects such as float on.
code_lines | grep -Fq 'windowrulev2' &&
  fail "windowrulev2 is deprecated on Hyprland 0.55.2"
code_lines | grep -Eq 'windowrule[[:space:]]*=[[:space:]]*match:class .*float on' ||
  fail "expected modern windowrule = match:class ..., float on for 0.55.x"
code_lines | grep -Eq 'windowrule[[:space:]]*=[[:space:]]*match:title .*float on' ||
  fail "expected modern windowrule = match:title ..., float on for 0.55.x"
grep -Fq '0.55' "$HYPR" ||
  fail "hyprland.nix must document Debian ~0.55.x target"
grep -Fq 'ryoku-start-dms' "$HYPR" ||
  fail "Hyprland must exec-once DMS"
! grep -Fq 'exec-once = niri' "$HYPR" ||
  fail "Hyprland must not start Niri"
! grep -Fq 'spawn-at-startup' "$HYPR" ||
  fail "Hyprland must not use Niri spawn-at-startup"

# Niri recovery must remain packaged even when hyprland is primary.
NIRI="$ROOT/distro/flake/home/niri.nix"
grep -Fq 'niri' "$NIRI" || fail "niri.nix missing niri package"
! grep -Fq 'mkIf enabled' "$NIRI" ||
  fail "niri.nix must not gate the whole module on compositor==niri (recovery)"
grep -Fq 'xdg.configFile."niri/config.kdl"' "$NIRI" ||
  fail "niri config.kdl must always be written for GDM recovery"

# Keep GDM/Hyprland environment compliant with 0.53+ startup advice.
SESSION="$ROOT/distro/session/ryoku-hyprland-session"
DESKTOP="$ROOT/distro/session/ryoku-hyprland.desktop"
APT="$ROOT/distro/apt/packages-hyprland.txt"
grep -Fq 'exec /usr/bin/start-hyprland' "$SESSION" ||
  fail "Ryoku GDM wrapper should prefer start-hyprland"
grep -Fq 'export XDG_CURRENT_DESKTOP="Hyprland"' "$SESSION" ||
  fail "GDM wrapper must not set XDG_CURRENT_DESKTOP=Hyprland:Ryoku"
grep -Fxq 'DesktopNames=Hyprland' "$DESKTOP" ||
  fail "GDM session should advertise canonical Hyprland desktop identifier"
grep -Fxq 'hyprland-guiutils' "$APT" ||
  fail "Debian backports GUI recovery helpers missing"
grep -Fq 'XDG_CURRENT_DESKTOP = "Hyprland";' "$HYPR" ||
  fail "Home Manager should export the canonical Hyprland desktop identifier"

pass "Hyprland conf targets Debian 0.55.x; Niri recovery always available"
