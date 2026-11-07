#!/usr/bin/env bash
# Mission 012 FINAL — Ryoku Minimal interactive QEMU helper.
# DEFAULT: plan + validate artifacts only. Does NOT start QEMU.
#
# Real guest boot requires ALL of:
#   RYOKU_MINIMAL_QEMU_EXECUTE=1
#   RYOKU_MINIMAL_QEMU_CONFIRM=RUN
# Never set those on Cursor hosts without separate human authorization.
#
# Safety: TCG only, -nic none, no physical disks, -display none -serial stdio -monitor none.
# Does not touch T3 file-serial evidence profile / ryoku-boot-seed.cpio.gz.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONF="$ROOT/tests/qemu/configs/console-interactive.rvl.conf"
T3_CONF="$ROOT/tests/qemu/configs/t3-boot-seed.rvl.conf"
KERNEL="$ROOT/tests/qemu/run/ryoku-boot-seed-vmlinuz"
INITRD="$ROOT/tests/qemu/run/ryoku-minimal.cpio.gz"
SUMS="$ROOT/tests/qemu/results/ryoku-minimal-SHA256SUMS.txt"
EXECUTE="${RYOKU_MINIMAL_QEMU_EXECUTE:-0}"
CONFIRM="${RYOKU_MINIMAL_QEMU_CONFIRM:-}"

echo "Ryoku Minimal QEMU helper (Mission 012 FINAL)"
echo "  config:   $CONF"
echo "  kernel:   $KERNEL"
echo "  initrd:   $INITRD"
echo "  execute:  $EXECUTE (0=plan/validate; 1 needs CONFIRM=RUN)"
echo "  confirm:  ${CONFIRM:-(empty)}"

fail() { echo "error: $*" >&2; exit 1; }

[[ -f "$CONF" ]] || fail "missing $CONF"
[[ -f "$T3_CONF" ]] || fail "missing T3 profile (must stay preserved)"
grep -q 'serial_log = stdio' "$CONF" || fail "interactive profile must use serial_log=stdio"
grep -q 'initrd = run/ryoku-minimal.cpio.gz' "$CONF" || fail "interactive must use Minimal initrd"
grep -q 'accel = tcg' "$CONF" || fail "must keep accel=tcg"
grep -q 'network = none' "$CONF" || fail "must keep network=none"
grep -q 'disk = none' "$CONF" || fail "must keep disk=none"
grep -q 'serial_log = results/serial-t3-boot-seed.log' "$T3_CONF" || fail "T3 file-serial changed"
grep -q 'initrd = run/ryoku-boot-seed.cpio.gz' "$T3_CONF" || fail "T3 initrd must stay boot-seed"
! grep -q 'ryoku-minimal' "$T3_CONF" || fail "T3 must not point at Minimal initrd"

echo
echo "PLAN (reproducible argv — not executed unless authorized):"
echo "  qemu-system-x86_64 \\"
echo "    -name ryoku-virtlab-console-interactive \\"
echo "    -accel tcg -m 256 -smp 1 \\"
echo "    -display none -nodefaults -nic none \\"
echo "    -kernel $KERNEL \\"
echo "    -initrd $INITRD \\"
echo "    -append 'console=ttyS0' \\"
echo "    -serial stdio -monitor none \\"
echo "    -machine type=pc"
echo
echo "Expected serial dialogue (future authorized run):"
echo "  ryoku-init: pid=1 … → RYOKU_BOOT_SEED_READY → interactive spawn → ryoku>"
echo "Honesty: interactive guest ≠ product OS boot. T3 evidence path stays separate."

missing=0
if [[ ! -f "$KERNEL" ]]; then
  echo "MISSING: lab kernel $KERNEL"
  missing=1
fi
if [[ ! -f "$INITRD" ]]; then
  echo "MISSING: Minimal initrd $INITRD"
  missing=1
fi
if [[ -f "$SUMS" ]]; then
  echo "Found checksums: $SUMS"
  # Validate listed files when present (ignore missing lines for optional paths).
  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$ROOT"
      # Check only files that exist; fail if a listed existing file mismatches.
      while read -r hash path; do
        [[ -z "${hash:-}" || "$hash" =~ ^# ]] && continue
        [[ -f "$path" ]] || continue
        echo "$hash  $path" | sha256sum -c -
      done <"$SUMS"
    ) || fail "SHA256SUMS mismatch"
    echo "OK: SHA256SUMS verified for present members"
  fi
else
  echo "NOTE: no SHA256SUMS yet at $SUMS (CI package workflow produces it)"
fi

if [[ "$missing" -eq 1 ]]; then
  echo "VALIDATE: incomplete artifacts — build via ryoku-minimal-package workflow / musl pack scripts"
  if [[ "$EXECUTE" == "1" ]]; then
    fail "refusing QEMU: required artifacts missing"
  fi
  echo "OK: plan printed; artifacts incomplete; QEMU NOT_RUN"
  exit 0
fi

echo "VALIDATE: kernel + Minimal initrd present"

if [[ "$EXECUTE" != "1" ]]; then
  echo "OK: plan+validate only. Set RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM=RUN for guest (authorized)."
  exit 0
fi

if [[ "$CONFIRM" != "RUN" ]]; then
  fail "RYOKU_MINIMAL_QEMU_EXECUTE=1 requires RYOKU_MINIMAL_QEMU_CONFIRM=RUN"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  fail "qemu-system-x86_64 not found (install only on disposable authorized runners)"
fi

echo "AUTHORIZED: starting QEMU (TCG, nic=none, serial=stdio)…"
exec qemu-system-x86_64 \
  -name ryoku-virtlab-console-interactive \
  -accel tcg \
  -m 256 \
  -smp 1 \
  -display none \
  -nodefaults \
  -nic none \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "console=ttyS0" \
  -serial stdio \
  -monitor none \
  -machine type=pc
