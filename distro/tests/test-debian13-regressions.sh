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

# First real GDM/Niri login failed on "unexpected node prefers-no-csd".
NIRI_KDL="$ROOT/distro/flake/home/niri.nix"
grep -Fq '    prefer-no-csd' "$NIRI_KDL" || fail "correct Niri KDL node missing"
! grep -Fq 'prefers-no-csd' "$NIRI_KDL" || fail "invalid prefers-no-csd still present"
grep -Fq '"$niri_bin" validate' "$BOOTSTRAP" ||
  fail "bootstrap does not validate Niri KDL after HM activation"
pass "Niri KDL syntax regression guarded"

# Verify Nix-installed compositor gets a Mesa wrapper rather than running
# directly (previously tried the NixOS-only /run/opengl-driver GBM location).
SESSION="$ROOT/distro/session/ryoku-niri-session"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
TEST_BIN="$TEST_HOME/.local/state/nix/profiles/home-manager/home-path/bin"
mkdir -p "$TEST_BIN"
printf '#!/bin/sh\nexit 97\n' > "$TEST_BIN/niri"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$RYOKU_TEST_SESSION_LOG"\n' > "$TEST_BIN/nixGLIntel"
chmod +x "$TEST_BIN/niri" "$TEST_BIN/nixGLIntel"
HOME="$TEST_HOME" RYOKU_TEST_SESSION_LOG="$TEST_HOME/session.log" bash "$SESSION" ||
  fail "Niri session wrapper failed"
EXPECTED="$TEST_BIN/niri --session"
[[ "$(cat "$TEST_HOME/session.log")" == "$EXPECTED" ]] ||
  fail "Niri session didn't invoke nixGLIntel with Niri --session"
pass "Niri starts through Mesa nixGLIntel"

# Regression from the first visual worktree bootstrap on Proxmox:
# .git is a file inside linked worktrees. The host was written but not staged,
# so a pure flake offered only homeConfigurations.ryoku (not paulo).
grep -Fq 'rev-parse --is-inside-work-tree' "$BOOTSTRAP" ||
  fail "worktree-aware Git detection missing"
grep -Fq 'ls-files --error-unmatch' "$BOOTSTRAP" ||
  fail "bootstrap must verify host actually reached Git index"
! grep -Fq '[[ -d "$REPO_ROOT/.git" ]]' "$BOOTSTRAP" ||
  fail "bootstrap still ignores linked worktrees"
mkdir -p "$TEST_HOME/worktree-fixture"
git -C "$TEST_HOME/worktree-fixture" init -q
git -C "$TEST_HOME/worktree-fixture" config user.name "Ryoku CI"
git -C "$TEST_HOME/worktree-fixture" config user.email "ryoku-ci@example.invalid"
printf 'baseline\n' > "$TEST_HOME/worktree-fixture/README"
git -C "$TEST_HOME/worktree-fixture" add README
git -C "$TEST_HOME/worktree-fixture" commit -q -m "initial"
git -C "$TEST_HOME/worktree-fixture" worktree add -q --detach "$TEST_HOME/linked"
[[ -f "$TEST_HOME/linked/.git" ]] ||
  fail "expected .git to be a file in linked worktree"
[[ "$(git -C "$TEST_HOME/linked" rev-parse --is-inside-work-tree)" == true ]] ||
  fail "Git rev-parse cannot recognize linked worktree"
mkdir -p "$TEST_HOME/linked/distro/flake/hosts/paulo"
printf '{ username = "paulo"; }\n' > "$TEST_HOME/linked/distro/flake/hosts/paulo/default.nix"
git -C "$TEST_HOME/linked" add -- distro/flake/hosts/paulo/default.nix
git -C "$TEST_HOME/linked" ls-files --error-unmatch -- distro/flake/hosts/paulo/default.nix >/dev/null ||
  fail "host not stageable from detached linked worktree"
pass "linked worktree host index and pure flake visibility"

# Ryoku DMS needs to autostart in the GDM direct-niri --session mode:
# that mode does not necessarily start graphical-session.target.
DMS_MODULE="$ROOT/distro/flake/home/dms.nix"
grep -Fq 'spawn-at-startup "${config.home.homeDirectory}/.local/bin/ryoku-start-dms"' "$NIRI_KDL" ||
  fail "Niri must start DMS directly for the tested Debian GDM session"
grep -Fq 'home.file.".local/bin/ryoku-start-dms"' "$DMS_MODULE" ||
  fail "DMS launcher missing from Home Manager"
grep -q 'nixGLIntel' "$DMS_MODULE" ||
  fail "DMS launcher missing pure Mesa wrapper"
# VM 201 first GUI login: DMS Go binary started but died because it cannot
# execute "qs" (Quickshell not available in GDM/Niri startup PATH).
grep -Fq 'pkgs.quickshell' "$DMS_MODULE" ||
  fail "Quickshell package missing from Home Manager"
grep -Fq 'lib.makeBinPath [ pkgs.quickshell ]' "$DMS_MODULE" ||
  fail "DMS launcher must explicitly prepend Quickshell to PATH"
! grep -Fq 'systemd.user.services.ryoku-dms' "$DMS_MODULE" ||
  fail "DMS may double-start via systemd user and Niri startup"
pass "Ryoku DMS startup wired for direct GDM Niri"

bash -n "$BOOTSTRAP" || fail "bootstrap bash syntax"
bash -n "$ROOT/distro/session/ryoku-niri-session" || fail "session shell syntax"
pass "shell syntax"
