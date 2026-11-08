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
mkdir -p "$TEST_BIN" "$TEST_HOME/runtime"
printf '#!/bin/sh\nexit 97\n' > "$TEST_BIN/niri"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$RYOKU_TEST_SESSION_LOG"\n' > "$TEST_BIN/nixGLIntel"
chmod +x "$TEST_BIN/niri" "$TEST_BIN/nixGLIntel"
# pam_systemd provides XDG_RUNTIME_DIR in real GDM sessions; the wrapper must
# refuse to invent /run/user/1000, so the harness supplies a temp runtime dir.
HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_HOME/runtime" \
  RYOKU_TEST_SESSION_LOG="$TEST_HOME/session.log" bash "$SESSION" ||
  fail "Niri session wrapper failed"
# Guard: missing runtime dir must fail closed (no hardcoded /run/user/1000).
if HOME="$TEST_HOME" env -u XDG_RUNTIME_DIR bash "$SESSION" 2>/dev/null; then
  fail "session started without XDG_RUNTIME_DIR"
fi
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
MATUGEN_MODULE="$ROOT/distro/flake/home/matugen.nix"
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
grep -Fq 'dmsRuntimePath = lib.makeBinPath' "$DMS_MODULE" ||
  fail "DMS runtime PATH must include Quickshell (qs) and DMS CLI"
grep -Fq 'pkgs.quickshell' "$DMS_MODULE" ||
  fail "Quickshell missing from DMS runtime PATH construction"
# VM 201 second GUI test: QML loaded successfully but subprocesses such as
# QList("dms", "blur", "check") failed because only qs was on PATH.
grep -Fq 'dmsRuntimePath' "$DMS_MODULE" ||
  fail "QML/SSH child processes cannot resolve the DMS CLI / qs"
# SSH `dms ipc` execs bare qs (DMS shell.go) — bare store dms alone is insufficient.
grep -Fq 'writeShellScriptBin "dms"' "$DMS_MODULE" ||
  fail "user-facing dms wrapper missing (SSH ipc needs qs on PATH)"
grep -Fq 'export PATH="${dmsRuntimePath}' "$DMS_MODULE" ||
  fail "apply/ipc helpers must export dmsRuntimePath before dms ipc"
# Competing long-running ryoku-dms.service would double-start with Niri spawn.
# Path oneshots (ryoku-dms-bar / ryoku-dms-session) are allowed.
! grep -Eq 'systemd\.user\.services\.ryoku-dms\s*=' "$DMS_MODULE" ||
  fail "long-running ryoku-dms systemd service must not compete with Niri spawn"
# ExecStart in this module must not launch the shell; only ryoku-start-dms does.
! grep -E 'ExecStart\s*=' "$DMS_MODULE" | grep -Eq 'dms.*run|/bin/dms"' ||
  fail "systemd must not ExecStart dms run alongside Niri spawn-at-startup"
pass "Ryoku DMS startup wired for direct GDM Niri"

# Quattro bar fidelity: DMS 1.5.3 reads barConfigs as an ARRAY of {id,...}.
# An object map (barConfigs.default=…) is ignored — Quattro strip never applies.
grep -Fq 'barConfigs = [ styleBar ]' "$DMS_MODULE" ||
  fail "Quattro seed must use barConfigs array (DMS SettingsData.find by id)"
grep -Fq 'leftWidgets' "$DMS_MODULE" ||
  fail "Quattro bar missing leftWidgets from ryoku-desktop"
grep -Fq 'workspaceSwitcher' "$DMS_MODULE" ||
  fail "Quattro bar missing workspaceSwitcher widget"
grep -Fq 'id = "default"' "$DMS_MODULE" ||
  fail "default bar id missing"
grep -Fq 'visible = true' "$DMS_MODULE" ||
  fail "Quattro bar must declaratively set visible = true"
grep -Fq 'autoHide = false' "$DMS_MODULE" ||
  fail "Quattro bar must declaratively disable autoHide"
# VM 201: IPC visible + reveal OK but niri msg layers had no Top quickshell surface.
# ShellCore Loader requires enabled=true; position int 0 = Top for getPosition.
grep -Fq 'enabled = true' "$DMS_MODULE" ||
  fail "Quattro bar must set enabled=true or DankBar never creates a layer-shell window"
grep -Fq 'position = 0' "$DMS_MODULE" ||
  fail "Quattro bar must set position=0 (Top) or getPosition returns unknown"
grep -Fq 'screenPreferences = [ "all" ]' "$DMS_MODULE" ||
  fail "Quattro bar must bind screenPreferences all for Virtual-1 / single monitors"
# Immutable store symlink would block DMS first-run persistence + bar merges.
! grep -Fq 'xdg.configFile."DankMaterialShell/settings.json"' "$DMS_MODULE" ||
  fail "DMS settings.json must stay mutable (no xdg.configFile symlink)"
grep -Fq 'seedRyokuDmsSettings' "$DMS_MODULE" ||
  fail "mutable settings seed activation missing"
grep -Fq 'apply-ryoku-dms-bar' "$DMS_MODULE" ||
  fail "Ryoku bar merge script missing"
pass "Quattro barConfigs array and mutable settings"

# GDM session PATH + absolute IPC helpers for DMS keybinds / launcher.
grep -Fq 'export PATH="${LOCAL_BIN}:${HM_BIN}:${NIX_BIN}:${PATH}"' "$SESSION" ||
  fail "ryoku-niri-session must prepend HM profile PATH for dms/qs"
grep -Fq 'ryoku-dms-ipc' "$NIRI_KDL" ||
  fail "Niri DMS IPC binds must use ryoku-dms-ipc absolute helper"
grep -Fq 'home.file.".local/bin/ryoku-dms-ipc"' "$DMS_MODULE" ||
  fail "ryoku-dms-ipc helper missing"
pass "DMS IPC PATH and absolute helpers"

# Matugen must eventually write ~/.config/niri/colors.kdl (VM observed missing).
grep -Fq 'ensureRyokuNiriColors' "$MATUGEN_MODULE" ||
  fail "colors.kdl seed activation missing"
grep -Fq 'niri/colors.kdl' "$MATUGEN_MODULE" ||
  fail "Matugen niri colors.kdl output path missing"
grep -Fq 'include optional=true "colors.kdl"' "$NIRI_KDL" ||
  fail "Niri must optionally include Matugen colors.kdl"
pass "Matugen Niri colors.kdl wiring"

# Fonts / theme parity with ryoku-desktop (not DejaVu-only placeholders).
KITTY="$ROOT/distro/flake/home/kitty.nix"
THEME="$ROOT/distro/flake/home/theme.nix"
grep -Fq 'JetBrainsMono Nerd Font' "$KITTY" ||
  fail "Kitty must use JetBrainsMono Nerd Font like ryoku-desktop"
grep -Fq 'nerd-fonts.jetbrains-mono' "$KITTY" ||
  fail "JetBrainsMono Nerd Font package missing"
grep -Fq 'platformTheme.name = "adwaita"' "$THEME" ||
  fail "Qt Adwaita platform theme missing"
pass "theme and font parity seeds"

# Master stabilize: no hardcoded seat sockets / uids; clear service ownership.
HARDCODE_HITS=$(
  grep -RInE 'wayland-1|/run/user/1000' "$ROOT/distro/session" "$ROOT/distro/flake/home" \
    --include='*.nix' --include='*.sh' --include='*.desktop' 2>/dev/null |
    grep -Ev 'Hardcod|hardcod|Never invent|never hardcode|Do not invent|ban' || true
)
[[ -z "$HARDCODE_HITS" ]] || {
  echo "$HARDCODE_HITS" >&2
  fail "hardcoded WAYLAND_DISPLAY or /run/user/1000 in session/HM sources"
}
grep -Fq 'XDG_RUNTIME_DIR unset' "$SESSION" ||
  fail "session must require pam XDG_RUNTIME_DIR"
grep -Fq 'already running' "$DMS_MODULE" ||
  fail "ryoku-start-dms must be idempotent against double spawn"
grep -Fq "pgrep -u \"\$uid\" -f -- 'quickshell'" "$DMS_MODULE" ||
  fail "idempotent start must detect Nix .quickshell-wrapped (not only -x qs)"
! grep -Fq 'pgrep -x quickshell' "$DMS_MODULE" ||
  fail "pgrep -x quickshell misses Nix wrapper process name"
grep -qx 'network-manager-gnome' "$APT_LIST" ||
  fail "network-manager-gnome required for nm-applet tray"
grep -qx 'mate-polkit' "$APT_LIST" ||
  fail "mate-polkit required for GUI pkexec under Niri"
grep -Fq 'ryoku-nm-applet' "$NIRI_KDL" ||
  fail "NM tray must use optional wrapper, not bare nm-applet only"
grep -Fq 'ryoku-polkit-agent' "$NIRI_KDL" ||
  fail "polkit agent must autostart under Niri"
grep -Fq 'ryoku-cliphist-text' "$NIRI_KDL" ||
  fail "cliphist text watcher missing (empty clipboard DB / timeouts)"
! grep -Eiq 'spawn-at-startup.*(mako|dunst|swaync)' "$NIRI_KDL" ||
  fail "DMS owns notifications — do not also spawn mako/dunst/swaync"
! grep -E 'usermod.*\binput\b|[[:space:]]-G[[:space:]]+input' "$BOOTSTRAP" ||
  fail "bootstrap must never auto-add users to the input group"
pass "session ownership, PATH hygiene, and security guards"

bash -n "$BOOTSTRAP" || fail "bootstrap bash syntax"
bash -n "$ROOT/distro/session/ryoku-niri-session" || fail "session shell syntax"
pass "shell syntax"
