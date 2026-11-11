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
code_lines | grep -Eq 'windowrule = float on,' &&
  fail "0.56 windowrule rewrite (float on, …) not allowed for Debian 0.55.x"
code_lines | grep -Fq 'new_optimizations' &&
  fail "blur:new_optimizations removed/unsafe for 0.55 target — omit it"
code_lines | grep -Fq 'no_anim on, match:namespace' &&
  fail "0.56 layerrule form banned; use classic layerrule = noanim, …"
# 0.55.2 deprecates windowrulev2 (startup overlay) — use windowrule + v2 args.
code_lines | grep -Fq 'windowrulev2' &&
  fail "windowrulev2 is deprecated on Hyprland 0.55.2 — use windowrule ="
code_lines | grep -Eq 'windowrule = float, class:' ||
  fail "expected windowrule = float, class:^(…) for 0.55.x"
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

pass "Hyprland conf targets Debian 0.55.x; Niri recovery always available"
