#!/usr/bin/env bash
# Mission 015 — standalone shell ZIP layout test (no QEMU).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAUNCHER="$ROOT/tests/qemu/scripts/run-ryoku-shell-qemu.sh"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-shell-zip-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PKG="$WORKDIR/pkg"
mkdir -p "$PKG"
cp -a "$LAUNCHER" "$PKG/run-ryoku-shell-qemu.sh"
chmod +x "$PKG/run-ryoku-shell-qemu.sh"
printf 'fake-lab-kernel\n' >"$PKG/ryoku-boot-seed-vmlinuz"
printf 'fake-shell-cpio\n' >"$PKG/ryoku-shell.cpio.gz"
(
  cd "$PKG"
  sha256sum ryoku-boot-seed-vmlinuz ryoku-shell.cpio.gz | tee SHA256SUMS.txt
)

echo "== shell standalone plan-only =="
OUT="$WORKDIR/out.txt"
RYOKU_SHELL_QEMU_EXECUTE=0 "$PKG/run-ryoku-shell-qemu.sh" >"$OUT" 2>&1
grep -q 'mode:     standalone' "$OUT"
grep -q 'OK: SHA256SUMS verified' "$OUT"
grep -q 'LAUNCHER_GUEST=NOT_RUN' "$OUT"
grep -q 'virtio-vga' "$OUT"
grep -q 'virtio-keyboard-pci' "$OUT"
grep -q 'virtio-tablet-pci' "$OUT"
echo "pass: shell_standalone_plan"

echo "== execute without CONFIRM must fail =="
if RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM= \
  "$PKG/run-ryoku-shell-qemu.sh" >"$WORKDIR/noc.out" 2>&1; then
  echo "FAIL: expected confirm gate"; exit 1
fi
echo "pass: shell_execute_gate"
echo "OK: test-ryoku-shell-vm-zip.sh (QEMU NOT_RUN)"
