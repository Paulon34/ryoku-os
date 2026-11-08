#!/usr/bin/env bash
# Policy / safety tests for ryoku-bootstrap (no root, no guest VM, no QEMU).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BOOTSTRAP="$ROOT/distro/scripts/ryoku-bootstrap"
FIX="$ROOT/distro/tests/fixtures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
  local name=$1
  shift
  if "$@"; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name" >&2
    fail=$((fail + 1))
  fi
}

check_fail() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $name (expected non-zero)" >&2
    fail=$((fail + 1))
  else
    echo "PASS: $name"
    pass=$((pass + 1))
  fi
}

[[ -x "$BOOTSTRAP" ]] || chmod +x "$BOOTSTRAP"

# Help works.
check "help exits 0" "$BOOTSTRAP" --help

# Missing mode fails.
check_fail "no mode fails" "$BOOTSTRAP"

# NixOS refused (dry-run).
check_fail "refuse NixOS dry-run" \
  "$BOOTSTRAP" --dry-run --sysroot "$FIX/pretend-nixos" --user alice --yes

# NixOS refused (apply).
check_fail "refuse NixOS apply" \
  "$BOOTSTRAP" --apply --sysroot "$FIX/pretend-nixos" --user alice --yes

# Debian fixture dry-run succeeds (no root needed).
check "debian fixture dry-run" \
  "$BOOTSTRAP" --dry-run --sysroot "$FIX/pretend-debian" --user alice \
  --log-dir "$TMP/logs" --backup-dir "$TMP/backup"

# Root user refused.
check_fail "refuse root user" \
  "$BOOTSTRAP" --dry-run --sysroot "$FIX/pretend-debian" --user root

# PASS_MANUAL may appear only as an explicit non-claim / do-not-invent warning.
if grep -n 'PASS_MANUAL' "$BOOTSTRAP" | grep -viE 'invent|do not|GUEST_NOT_RUN|não invent'; then
  echo "FAIL: suspicious PASS_MANUAL claim in bootstrap" >&2
  fail=$((fail + 1))
else
  echo "PASS: no invented PASS_MANUAL success path"
  pass=$((pass + 1))
fi

# Must refuse / document GRUB+partition out of scope.
check "mentions GRUB refuse" grep -q 'GRUB' "$BOOTSTRAP"
check "mentions GUEST_NOT_RUN" grep -q 'GUEST_NOT_RUN' "$BOOTSTRAP"

# Must not call qemu.
check_fail "no qemu references in bootstrap" grep -qiE 'qemu-system|qemu-img' "$BOOTSTRAP"

# Apply on fixture should not require host debian and should not touch real /etc.
check "debian fixture apply (no host mutate)" \
  "$BOOTSTRAP" --apply --sysroot "$FIX/pretend-debian" --user alice --yes \
  --log-dir "$TMP/logs-apply" --backup-dir "$TMP/backup-apply" --skip-hm

# Fixture apply should have written session under sysroot... but our install paths
# use SYSROOT prefix — verify desktop landed under fixture.
if [[ -f "$FIX/pretend-debian/usr/share/wayland-sessions/ryoku-niri.desktop" ]] || \
   [[ -f "$TMP/backup-apply/RECOVERY.md" ]]; then
  echo "PASS: fixture apply produced recovery or session artifacts"
  pass=$((pass + 1))
else
  # Recovery is under backup-dir; session under sysroot.
  if [[ -f "$TMP/backup-apply/RECOVERY.md" ]]; then
    echo "PASS: recovery notes written"
    pass=$((pass + 1))
  else
    echo "FAIL: fixture apply produced no recovery notes" >&2
    fail=$((fail + 1))
  fi
fi

# Cleanup fixture mutations under pretend-debian (keep os-release only).
rm -rf "$FIX/pretend-debian/usr" "$FIX/pretend-debian/var" "$FIX/pretend-debian/etc/nix" 2>/dev/null || true

echo
echo "Summary: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
