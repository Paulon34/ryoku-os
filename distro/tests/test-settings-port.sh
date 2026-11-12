#!/usr/bin/env bash
# Static checks for Ryoku Settings Debian port (no Qt build / no guest).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0

pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

require() {
  local p=$1
  if [[ -e "$ROOT/$p" ]]; then
    pass "$p"
  else
    fail_msg "missing $p"
  fi
}

require distro/apps/ryoku-settings/CMakeLists.txt
require distro/apps/ryoku-settings/src/main.cpp
require distro/apps/ryoku-settings/resources/org.ryoku.Settings.desktop
require distro/apps/ryoku-settings-apply/src/main.cpp
require distro/apps/ryoku-settings-apply/src/ops.c
require distro/flake/pkgs/ryoku-settings.nix
require distro/flake/pkgs/ryoku-settings-apply.nix
require distro/flake/home/settings.nix
require distro/polkit/org.ryoku.settings.apply.policy
require distro/ryoku/settings.json
require distro/ryoku/lib.nix
require ryoku/settings.json

# Debian adaptations present
grep -Fq 'distro/flake/flake.nix' "$ROOT/distro/apps/ryoku-settings/src/RepoPath.cpp" \
  || fail_msg "RepoPath must accept Debian Modular layout"
grep -Fq '/usr/bin/pkexec' "$ROOT/distro/apps/ryoku-settings/src/ApplyController.h" \
  || fail_msg "ApplyController must allow Debian pkexec"
grep -Fq 'home-manager' "$ROOT/distro/apps/ryoku-settings-apply/src/main.cpp" \
  || fail_msg "settings-apply must call home-manager (not only nixos-rebuild)"
grep -Fq 'home-manager-' "$ROOT/distro/apps/ryoku-settings-apply/src/ops.c" \
  || fail_msg "ops.c must validate HM generation links"
# Apply path must call home-manager; nixos-rebuild may appear only in comments.
grep -Eq 'home-manager' "$ROOT/distro/apps/ryoku-settings-apply/src/main.cpp" \
  || fail_msg "settings-apply must reference home-manager"
# No executable token for nixos-rebuild (comment-only mention is OK).
if grep -E '"(nixos-rebuild)"|execv\(.*nixos-rebuild' "$ROOT/distro/apps/ryoku-settings-apply/src/main.cpp" >/dev/null; then
  fail_msg "Debian settings-apply must not exec nixos-rebuild"
fi
# switch-generation must activate the chosen generation — not rebuild via do_apply.
grep -Fq '/activate' "$ROOT/distro/apps/ryoku-settings-apply/src/main.cpp" \
  || fail_msg "switch-generation must exec generation activate script"
# Ensure no executable return do_apply inside do_switch_generation body (comments OK).
if awk '/^static int do_switch_generation/,/^static int |^int main/' \
     "$ROOT/distro/apps/ryoku-settings-apply/src/main.cpp" \
     | grep -E '^[[:space:]]*return do_apply\(' >/dev/null; then
  fail_msg "switch-generation must not call do_apply (would rebuild from source)"
fi
# repoPath must not default-guess ~/ryoku-os
! grep -Fq 'defaultRepo' "$ROOT/distro/flake/home/settings.nix" \
  || fail_msg "settings.nix must not invent defaultRepo ~/ryoku-os"
grep -Fq 'repoPath = "";' "$ROOT/distro/flake/hosts/ryoku/default.nix" \
  || fail_msg "example host must leave settingsApply.repoPath empty"
grep -Fq 'repoPath = "$repo_path"' "$ROOT/distro/scripts/ryoku-bootstrap" \
  || fail_msg "bootstrap must bake REPO_ROOT into settingsApply.repoPath"
grep -Fq '/usr/local/libexec/ryoku-settings-apply' "$ROOT/distro/polkit/org.ryoku.settings.apply.policy" \
  || fail_msg "polkit policy must use stable libexec path"
grep -Fq 'matugen' "$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp" \
  || fail_msg "WallpaperApplier must trigger matugen persistence"
grep -Fq 'current-wallpaper' "$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp" \
  || fail_msg "WallpaperApplier must persist current-wallpaper symlink"

# Desktop entry contract
desk="$ROOT/distro/apps/ryoku-settings/resources/org.ryoku.Settings.desktop"
grep -q '^Exec=ryoku-settings$' "$desk" || fail_msg "desktop Exec"
grep -q '^Terminal=false$' "$desk" || fail_msg "desktop Terminal"
grep -q '^Icon=org.ryoku.Settings$' "$desk" || fail_msg "desktop Icon"
! grep -q '^X-GNOME-Autostart' "$desk" || fail_msg "desktop must not autostart"

# HM imports
grep -Fq './settings.nix' "$ROOT/distro/flake/home/home.nix" || fail_msg "home.nix must import settings.nix"
grep -Fq './build-info.nix' "$ROOT/distro/flake/home/home.nix" || fail_msg "home.nix must import build-info.nix"

# Debian Qt needs nixGL wrap (guest: EGL/RHI abort without it)
grep -Fq 'nixGLIntel' "$ROOT/distro/flake/home/settings.nix" \
  || fail_msg "settings.nix must wrap ryoku-settings with nixGLIntel"
grep -Fq 'settingsBin' "$ROOT/distro/flake/home/settings.nix" \
  || fail_msg "settings launcher must exec absolute store binary (no PATH loop)"
grep -Fq 'ryoku-settings-unwrapped' "$ROOT/distro/flake/home/settings.nix" \
  || fail_msg "settings.nix must expose unwrapped debug binary"
# Bootstrap must not seed invalid applied hash as file contents
! grep -E "printf .*unapplied" "$ROOT/distro/scripts/ryoku-bootstrap" \
  || fail_msg "bootstrap must not write invalid applied-settings-hash placeholder"

# Bootstrap wires polkit + libexec
grep -Fq 'install_settings_helper' "$ROOT/distro/scripts/ryoku-bootstrap" \
  || fail_msg "bootstrap must install settings helper"
grep -Fq 'packages-full.txt' "$ROOT/distro/scripts/ryoku-bootstrap" \
  || fail_msg "bootstrap must know packages-full"

# Compile apply helper ops (C only — no Qt needed)
tmpdir=$(mktemp -d)
cc -std=c11 -c "$ROOT/distro/apps/ryoku-settings-apply/src/ops.c" -I"$ROOT/distro/apps/ryoku-settings-apply/src" -o "$tmpdir/ops.o" \
  && pass "ops.c compiles" \
  || fail_msg "ops.c compile failed"
rm -rf "$tmpdir"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (settings-port)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
