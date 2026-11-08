#!/usr/bin/env bash
# Path / structure checks for the distro/ tree (ENTREGA A).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0

require() {
  local p=$1
  if [[ -e "$ROOT/$p" ]]; then
    echo "ok: $p"
  else
    echo "missing: $p" >&2
    fail=$((fail + 1))
  fi
}

require distro/README.pt-BR.md
require distro/THIRD_PARTY_NOTICES.md
require distro/docs/RYOKU_DEBIAN_ARCHITECTURE.md
require distro/scripts/ryoku-bootstrap
require distro/apt/packages-base.txt
require distro/flake/flake.nix
require distro/flake/home/home.nix
require distro/flake/home/niri.nix
require distro/flake/home/kitty.nix
require distro/flake/home/fuzzel.nix
require distro/flake/home/theme.nix
require distro/flake/home/nixgl.nix
require distro/flake/modules/profiles.nix
require distro/flake/hosts/ryoku/default.nix
require distro/session/ryoku-niri.desktop
require distro/session/ryoku-niri-session
require distro/tests/test-bootstrap-policy.sh
require distro/tests/test-hm-hosts.sh
require docs/migration/HYPRLAND_TO_NIRI_KEYBINDS.md

# Standalone HM: modules must not take/use osConfig (comments mentioning the ban are OK).
if grep -E '^[^#]*\bosConfig\b' "$ROOT/distro/flake/home/"*.nix; then
  echo "FAIL: osConfig reference in standalone HM modules" >&2
  fail=$((fail + 1))
else
  echo "ok: no osConfig in distro/flake/home"
fi

# nix-setup-systemd preferred in docs/script.
if grep -q 'nix-setup-systemd' "$ROOT/distro/scripts/ryoku-bootstrap" \
  && grep -q 'nix-setup-systemd' "$ROOT/distro/apt/packages-base.txt"; then
  echo "ok: nix-setup-systemd preferred"
else
  echo "FAIL: nix-setup-systemd not wired" >&2
  fail=$((fail + 1))
fi

# Bootstrap executable bit (git may not preserve in all checkouts; script should be +x in tree).
if [[ -x "$ROOT/distro/scripts/ryoku-bootstrap" ]]; then
  echo "ok: bootstrap executable"
else
  echo "FAIL: bootstrap not executable" >&2
  fail=$((fail + 1))
fi

# Shell syntax.
bash -n "$ROOT/distro/scripts/ryoku-bootstrap"
bash -n "$ROOT/distro/session/ryoku-niri-session"
bash -n "$ROOT/distro/tests/test-bootstrap-policy.sh"
bash -n "$ROOT/distro/tests/test-distro-paths.sh"
echo "ok: bash -n syntax"

[[ "$fail" -eq 0 ]]
