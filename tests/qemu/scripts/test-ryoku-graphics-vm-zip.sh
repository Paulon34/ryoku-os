#!/usr/bin/env bash
# Mission 014 — standalone graphics ZIP layout test (no QEMU).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAUNCHER="$ROOT/tests/qemu/scripts/run-ryoku-graphics-qemu.sh"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-graphics-zip-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PKG="$WORKDIR/pkg"
mkdir -p "$PKG"
cp -a "$LAUNCHER" "$PKG/run-ryoku-graphics-qemu.sh"
chmod +x "$PKG/run-ryoku-graphics-qemu.sh"
printf 'fake-lab-kernel\n' >"$PKG/ryoku-boot-seed-vmlinuz"
printf 'fake-graphics-cpio\n' >"$PKG/ryoku-graphics.cpio.gz"
(
  cd "$PKG"
  sha256sum ryoku-boot-seed-vmlinuz ryoku-graphics.cpio.gz | tee SHA256SUMS.txt
)

echo "== graphics standalone plan-only =="
OUT="$WORKDIR/out.txt"
RYOKU_GRAPHICS_QEMU_EXECUTE=0 "$PKG/run-ryoku-graphics-qemu.sh" >"$OUT" 2>&1
grep -q 'mode:     standalone' "$OUT"
grep -q 'OK: SHA256SUMS verified' "$OUT"
grep -q 'FIRST_PIXELS=NOT_RUN' "$OUT"
grep -q 'virtio-vga' "$OUT"
echo "pass: graphics_standalone_plan"

echo "== execute without CONFIRM must fail =="
if RYOKU_GRAPHICS_QEMU_EXECUTE=1 RYOKU_GRAPHICS_QEMU_CONFIRM= \
  "$PKG/run-ryoku-graphics-qemu.sh" >"$WORKDIR/noc.out" 2>&1; then
  echo "FAIL: expected confirm gate"; exit 1
fi
echo "pass: graphics_execute_gate"
echo "OK: test-ryoku-graphics-vm-zip.sh (QEMU NOT_RUN)"
