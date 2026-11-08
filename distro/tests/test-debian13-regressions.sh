#!/usr/bin/env bash
# Regressions observed in real Debian 13 / Proxmox VM (no root / guest required).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BOOTSTRAP="$ROOT/distro/scripts/ryoku-bootstrap"
APT_LIST="$ROOT/distro/apt/packages-base.txt"
NIXGL="$ROOT/distro/flake/home/nixgl.nix"
FLAKE="$ROOT/distro/flake/flake.nix"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Debian 13 no longer ships policykit-1; polkitd/pkexec replace it.
! grep -qx 'policykit-1' "$APT_LIST" || fail "obsolete policykit-1 in APT list"
grep -qx 'polkitd' "$APT_LIST" || fail "polkitd missing"
grep -qx 'pkexec' "$APT_LIST" || fail "pkexec missing"
pass "Debian 13 polkit packages"

# nixGLDefault auto NVIDIA detection uses builtins.currentTime (impure).
! grep -q 'wrappers.nixGLDefault' "$NIXGL" || fail "impure nixGLDefault in HM"
grep -q 'wrappers.nixGLIntel' "$NIXGL" || fail "pure Mesa wrapper missing"
grep -q 'nixGLIntel;' "$FLAKE" || fail "flake pure default missing"
pass "pure nixGL for standalone Home Manager"

# The first real VM failed because root created hosts/<user> before sudo-user tee.
grep -Fq 'install -d -m 0755 -o "$TARGET_USER"' "$BOOTSTRAP" ||
  fail "HM host directory is not owned by desktop user"
grep -Fq 'sudo -u "$TARGET_USER" tee "$path"' "$BOOTSTRAP" ||
  fail "HM host module not written as target user"
! grep -Fq 'sudo -u "$SUDO_USER" mkdir -p "$(dirname "$path")"' "$BOOTSTRAP" ||
  fail "old root-owned host directory logic still present"
pass "HM host permissions"

# On Debian, nix-setup-systemd may have an active service and inactive socket.
grep -q 'is-active --quiet nix-daemon.service' "$BOOTSTRAP" ||
  fail "active nix-daemon.service not recognized"
grep -Fq 'usermod -a -G nix-users "$TARGET_USER"' "$BOOTSTRAP" ||
  fail "desktop user not added to nix-users"
! grep -Fq 'usermod -a -G nixbld "$TARGET_USER"' "$BOOTSTRAP" ||
  fail "desktop user still assigned to build-worker group"
pass "Nix daemon and user authorization"

# Debian's gdm.service is static. PipeWire is a login-user service.
! grep -q 'systemctl enable gdm.service' "$BOOTSTRAP" ||
  fail "attempts to enable static gdm.service"
grep -q 'systemctl cat display-manager.service' "$BOOTSTRAP" ||
  fail "display manager not checked"
! grep -Fq 'sudo -u "$TARGET_USER" systemctl --user enable --now' "$BOOTSTRAP" ||
  fail "tries to start PipeWire without a login D-Bus session"
pass "GDM and PipeWire startup policy"

# Headless SSH Home Manager activation requires a functioning session bus.
# Debian 13 puts session.conf in /usr/share, whereas Nix dbus-run-session's
# bundled daemon may look for /etc/dbus-1/session.conf and fail on dconfSettings.
grep -qx 'dbus-daemon' "$APT_LIST" || fail "dbus-daemon not explicitly installed"
grep -qx 'dbus-session-bus-common' "$APT_LIST" || fail "D-Bus session config package missing"
grep -Fq '/usr/bin/dbus-run-session --' "$BOOTSTRAP" ||
  fail "HM switch not wrapped in Debian D-Bus session"
grep -Fq '[[ -f /usr/share/dbus-1/session.conf ]]' "$BOOTSTRAP" ||
  fail "missing Debian session.conf preflight before HM activation"
pass "D-Bus session for Home Manager dconfSettings"

bash -n "$BOOTSTRAP" || fail "bootstrap bash syntax"
bash -n "$ROOT/distro/session/ryoku-niri-session" || fail "session shell syntax"
pass "shell syntax"
