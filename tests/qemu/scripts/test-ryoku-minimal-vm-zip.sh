#!/usr/bin/env bash
# Mission 012.1 — exercise standalone ZIP layout without repo tree / without QEMU.
# Creates a disposable package dir, writes SHA256SUMS, runs launcher plan-only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAUNCHER="$ROOT/tests/qemu/scripts/run-ryoku-minimal-qemu.sh"
[[ -x "$LAUNCHER" || -f "$LAUNCHER" ]] || { echo "missing launcher" >&2; exit 1; }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-minimal-zip.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PKG="$WORKDIR/vm-zip"
mkdir -p "$PKG"

# Dummy blobs (not real kernels — hash gate only).
printf 'fake-lab-kernel\n' >"$PKG/ryoku-boot-seed-vmlinuz"
printf 'fake-minimal-cpio\n' >"$PKG/ryoku-minimal.cpio.gz"
cp -a "$LAUNCHER" "$PKG/run-ryoku-minimal-qemu.sh"
chmod +x "$PKG/run-ryoku-minimal-qemu.sh"
# Minimal conf (optional for standalone; include to exercise conf checks).
cat >"$PKG/console-interactive.rvl.conf" <<'EOF'
name = console-interactive
memory_mb = 256
cpus = 1
timeout_secs = 300
accel = tcg
network = none
disk = none
kernel = run/ryoku-boot-seed-vmlinuz
initrd = run/ryoku-minimal.cpio.gz
append = console=ttyS0
iso = none
serial_log = stdio
shutdown = none
EOF

(
  cd "$PKG"
  sha256sum ryoku-boot-seed-vmlinuz ryoku-minimal.cpio.gz | tee SHA256SUMS.txt
)

echo "== standalone plan-only (expect OK) =="
OUT="$WORKDIR/plan.out"
if ! RYOKU_MINIMAL_QEMU_EXECUTE=0 "$PKG/run-ryoku-minimal-qemu.sh" >"$OUT" 2>&1; then
  echo "FAIL: standalone plan should succeed" >&2
  cat "$OUT" >&2
  exit 1
fi
grep -q 'mode:     standalone' "$OUT" || { echo "FAIL: expected standalone mode"; cat "$OUT"; exit 1; }
grep -q 'OK: SHA256SUMS verified' "$OUT" || { echo "FAIL: expected hash verify"; cat "$OUT"; exit 1; }
grep -q 'OK: plan+validate only' "$OUT" || { echo "FAIL: expected plan-only"; cat "$OUT"; exit 1; }
if grep -q 'AUTHORIZED: starting QEMU' "$OUT"; then
  echo "FAIL: must not start QEMU" >&2
  exit 1
fi
# Standalone must not mention missing T3 profile as an error path.
if grep -qi 'missing T3' "$OUT"; then
  echo "FAIL: standalone must not require T3 files" >&2
  cat "$OUT" >&2
  exit 1
fi
echo "pass: standalone_plan"

echo "== tampered hash must fail =="
echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  ryoku-boot-seed-vmlinuz" >"$PKG/SHA256SUMS.txt"
echo "0000000000000000000000000000000000000000000000000000000000000000  ryoku-minimal.cpio.gz" >>"$PKG/SHA256SUMS.txt"
if RYOKU_MINIMAL_QEMU_EXECUTE=0 "$PKG/run-ryoku-minimal-qemu.sh" >"$WORKDIR/bad.out" 2>&1; then
  echo "FAIL: bad hashes should fail" >&2
  cat "$WORKDIR/bad.out" >&2
  exit 1
fi
echo "pass: bad_hash_refused"

echo "== missing SUMS must fail =="
rm -f "$PKG/SHA256SUMS.txt"
if RYOKU_MINIMAL_QEMU_EXECUTE=0 "$PKG/run-ryoku-minimal-qemu.sh" >"$WORKDIR/nosums.out" 2>&1; then
  echo "FAIL: missing SHA256SUMS.txt should fail" >&2
  cat "$WORKDIR/nosums.out" >&2
  exit 1
fi
echo "pass: missing_sums_refused"

echo "== EXECUTE without CONFIRM must fail (no QEMU) =="
(
  cd "$PKG"
  sha256sum ryoku-boot-seed-vmlinuz ryoku-minimal.cpio.gz | tee SHA256SUMS.txt >/dev/null
)
if RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM= "$PKG/run-ryoku-minimal-qemu.sh" >"$WORKDIR/nocconfirm.out" 2>&1; then
  echo "FAIL: EXECUTE=1 without CONFIRM=RUN should fail" >&2
  cat "$WORKDIR/nocconfirm.out" >&2
  exit 1
fi
if grep -q 'AUTHORIZED: starting QEMU' "$WORKDIR/nocconfirm.out"; then
  echo "FAIL: must not reach QEMU without CONFIRM" >&2
  exit 1
fi
echo "pass: execute_gate"

echo "OK: test-ryoku-minimal-vm-zip.sh — all cases passed (QEMU NOT_RUN)"
