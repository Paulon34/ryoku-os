#!/usr/bin/env bash
# Path / structure checks for the distro/ tree (ENTREGA A/B).
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
require distro/apt/packages-full.txt
require distro/flake/flake.nix
require distro/flake/home/home.nix
require distro/flake/home/niri.nix
require distro/flake/home/hyprland.nix
require distro/flake/home/session-helpers.nix
require distro/flake/home/kitty.nix
require distro/flake/home/fuzzel.nix
require distro/flake/home/theme.nix
require distro/flake/home/nixgl.nix
require distro/flake/home/dms.nix
require distro/flake/home/matugen.nix
require distro/flake/home/settings.nix
require distro/flake/home/build-info.nix
require distro/flake/pkgs/dms-shell-ryoku.nix
require distro/flake/pkgs/ryoku-settings.nix
require distro/flake/pkgs/ryoku-settings-apply.nix
require distro/flake/patches/dms/1.5.3/ryoku-quattro-foundation.patch
require distro/assets/wallpapers/ryoku-night.jpg
require distro/LICENSES/MIT-DankMaterialShell.txt
require distro/flake/modules/profiles.nix
require distro/flake/hosts/ryoku/default.nix
require distro/flake/hosts/ryoku-islands/default.nix
require distro/session/ryoku-niri.desktop
require distro/session/ryoku-niri-session
require distro/session/ryoku-hyprland.desktop
require distro/session/ryoku-hyprland-session
require distro/apt/packages-hyprland.txt
require distro/polkit/org.ryoku.settings.apply.policy
require distro/scripts/ryoku-doctor
require distro/apps/ryoku-settings/CMakeLists.txt
require distro/apps/ryoku-settings-apply/CMakeLists.txt
require distro/ryoku/settings.json
require distro/ryoku/lib.nix
require ryoku/settings.json
require distro/flake/home/matugen/templates/ryoku-hyprland.conf
require distro/flake/home/matugen/templates/ryoku-hyprland-quattro.conf
require distro/tests/test-bootstrap-policy.sh
require distro/tests/test-hm-hosts.sh
require distro/tests/test-debian13-regressions.sh
require distro/tests/test-dms-bar-merge.sh
require distro/tests/test-dms-ipc-path.sh
require distro/tests/test-dms-bar-surface.sh
require distro/tests/test-hyprland-conf-055.sh
require distro/tests/test-ryoku-doctor.sh
require distro/tests/test-settings-port.sh
require distro/tests/test-apt-groups.sh
require distro/docs/COMPOSITOR.md
require distro/docs/SERVICE_OWNERSHIP.md
require distro/docs/DMS_BAR_SURFACE.md
require distro/docs/ISLANDS_V4_PORT.md
require distro/docs/RYOKU_PROFILE_MVP.md
require distro/docs/NIXOS_TO_DEBIAN_MIGRATION_MATRIX.md
require distro/docs/VM_APPLY.md
require distro/docs/BARE_METAL_MIGRATION.md
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
bash -n "$ROOT/distro/scripts/ryoku-doctor"
bash -n "$ROOT/distro/session/ryoku-niri-session"
bash -n "$ROOT/distro/session/ryoku-hyprland-session"
bash -n "$ROOT/distro/tests/test-bootstrap-policy.sh"
bash -n "$ROOT/distro/tests/test-distro-paths.sh"
bash -n "$ROOT/distro/tests/test-debian13-regressions.sh"
bash -n "$ROOT/distro/tests/test-dms-bar-merge.sh"
bash -n "$ROOT/distro/tests/test-dms-ipc-path.sh"
bash -n "$ROOT/distro/tests/test-dms-bar-surface.sh"
bash -n "$ROOT/distro/tests/test-hyprland-conf-055.sh"
bash -n "$ROOT/distro/tests/test-ryoku-doctor.sh"
bash -n "$ROOT/distro/tests/test-settings-port.sh"
bash -n "$ROOT/distro/tests/test-apt-groups.sh"
echo "ok: bash -n syntax"

bash "$ROOT/distro/tests/test-hyprland-conf-055.sh" || fail=$((fail + 1))

[[ "$fail" -eq 0 ]]