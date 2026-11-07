#!/usr/bin/env bash
# Mission 012 — dry-run helper for the interactive Ryoku Minimal QEMU profile.
# DEFAULT: dry-run (print plan only). Never boots QEMU here.
# Does not download ISOs, install packages, or dispatch workflows.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONF="$ROOT/tests/qemu/configs/console-interactive.rvl.conf"
T3_CONF="$ROOT/tests/qemu/configs/t3-boot-seed.rvl.conf"
EXECUTE="${RYOKU_CONSOLE_INTERACTIVE_EXECUTE:-0}"

echo "Ryoku Minimal interactive prep (Mission 012)"
echo "  config:   $CONF"
echo "  execute:  $EXECUTE (0=dry-run; real guest boot NOT authorized in Mission 012)"

if [[ ! -f "$CONF" ]]; then
  echo "error: missing $CONF" >&2
  exit 1
fi
if [[ ! -f "$T3_CONF" ]]; then
  echo "error: T3 profile missing — refuse to proceed without preserved file-serial seed" >&2
  exit 1
fi

if ! grep -q 'serial_log = stdio' "$CONF"; then
  echo "error: interactive profile must use serial_log = stdio" >&2
  exit 1
fi
if ! grep -q 'initrd = run/ryoku-minimal.cpio.gz' "$CONF"; then
  echo "error: interactive profile must use Minimal initrd (ryoku-minimal.cpio.gz)" >&2
  exit 1
fi
if ! grep -q 'serial_log = results/serial-t3-boot-seed.log' "$T3_CONF"; then
  echo "error: T3 file-serial path changed unexpectedly" >&2
  exit 1
fi
if grep -q 'serial_log = stdio' "$T3_CONF"; then
  echo "error: T3 profile must NOT use stdio serial" >&2
  exit 1
fi
if grep -q 'ryoku-minimal' "$T3_CONF"; then
  echo "error: T3 profile must keep boot-seed initrd (not Minimal)" >&2
  exit 1
fi
if ! grep -q 'accel = tcg' "$CONF"; then
  echo "error: interactive profile must keep accel = tcg" >&2
  exit 1
fi
if ! grep -q 'network = none' "$CONF"; then
  echo "error: interactive profile must keep network = none" >&2
  exit 1
fi
if ! grep -q 'disk = none' "$CONF"; then
  echo "error: interactive profile must keep disk = none" >&2
  exit 1
fi

echo
echo "DRY-RUN plan (reproducible; do not run QEMU here):"
echo "  1. Preserve T3: ryoku-init READY/pid1 + file serial (unchanged profile)"
echo "  2. Build Minimal initramfs (dry-run):"
echo "       tests/qemu/scripts/build-ryoku-minimal-initramfs.sh"
echo "  3. Host tests: cargo test --workspace (no QEMU)"
echo "  4. Future auth: kernel + ryoku-minimal.cpio.gz + QEMU -serial stdio"
echo "       (see plan-minimal-guest-console-test.sh)"
echo "  5. Example future argv shape (NOT executed):"
echo "       qemu-system-x86_64 -accel tcg -m 256 -smp 1 -display none"
echo "         -nodefaults -nic none -monitor none -serial stdio"
echo "         -kernel run/ryoku-boot-seed-vmlinuz"
echo "         -initrd run/ryoku-minimal.cpio.gz"
echo "         -append 'console=ttyS0' -machine type=pc"
echo
echo "NOTE: Mission 012 stops before guest boot. RYOKU_CONSOLE_INTERACTIVE_EXECUTE=1 refused."

if [[ "$EXECUTE" == "1" ]]; then
  echo "error: refusing real interactive boot in Mission 012" >&2
  exit 1
fi

exit 0
