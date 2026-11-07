#!/usr/bin/env bash
# Mission 012 — plan for a future *authorized* automated guest console harness.
# DEFAULT: print plan only. NEVER runs QEMU. NEVER downloads kernels/ISOs.
#
# Refuses RYOKU_MINIMAL_GUEST_TEST_EXECUTE=1 in this mission (prep only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONF="$ROOT/tests/qemu/configs/console-interactive.rvl.conf"
T3_CONF="$ROOT/tests/qemu/configs/t3-boot-seed.rvl.conf"
EXECUTE="${RYOKU_MINIMAL_GUEST_TEST_EXECUTE:-0}"

echo "Ryoku Minimal — automated guest console test plan (Mission 012)"
echo "  interactive config: $CONF"
echo "  T3 config (must stay file-serial): $T3_CONF"
echo "  execute: $EXECUTE (must remain 0 here)"

if [[ ! -f "$CONF" ]]; then
  echo "error: missing $CONF" >&2
  exit 1
fi
if ! grep -q 'serial_log = stdio' "$CONF"; then
  echo "error: interactive profile must use serial_log = stdio" >&2
  exit 1
fi
if ! grep -q 'initrd = run/ryoku-minimal.cpio.gz' "$CONF"; then
  echo "error: interactive profile must use Minimal initrd" >&2
  exit 1
fi
if ! grep -q 'serial_log = results/serial-t3-boot-seed.log' "$T3_CONF"; then
  echo "error: T3 file-serial path changed" >&2
  exit 1
fi
if grep -q 'ryoku-minimal' "$T3_CONF"; then
  echo "error: T3 profile must not point at Minimal initrd" >&2
  exit 1
fi

cat <<'PLAN'

FUTURE AUTHORIZED HARNESS (do not run in Mission 012)
=====================================================
Prereqs (authorized disposable builder only):
  1. Lab kernel: tests/qemu/run/ryoku-boot-seed-vmlinuz (existing T2/T3 channel)
  2. RYOKU_MINIMAL_INITRAMFS_EXECUTE=1 tests/qemu/scripts/build-ryoku-minimal-initramfs.sh
  3. Explicit auth env, e.g. RYOKU_MINIMAL_GUEST_TEST_EXECUTE=1 (not implemented to run yet)

Expected guest serial dialogue (stdio):
  A. Observe: `ryoku-init: pid=1` then `RYOKU_BOOT_SEED_READY` (from PID 1 only)
  B. Observe: `ryoku-init: interactive mode — spawning /bin/ryoku-console`
  C. Observe: `ryoku-console` banner + `ryoku> ` prompt
  D. Send:  help\n     → builtins list (includes pwd/ls/cat)
  E. Send:  pwd\n      → /home/ryoku
  F. Send:  ls /etc\n  → ryoku-release
  G. Send:  cat /etc/ryoku-release\n → ryoku-minimal …
  H. Send:  status\n   → honesty blurb; must NOT claim product OS boot
  I. Close stdin / exit console → PID 1 remains (no kernel panic from init exit)

Host unit stand-in (already runnable, no QEMU):
  cargo test -p ryoku-console
  cargo test -p ryoku-init
  cargo test -p ryoku-virtlab -- initramfs

Hard rules for any future run:
  - TCG only, network=none, no physical disks
  - Do not overwrite/replace t3-boot-seed.rvl.conf file-serial evidence
  - Console must never emit READY as boot evidence
  - No workflow_dispatch from this plan script

PLAN

if [[ "$EXECUTE" == "1" ]]; then
  echo "error: refusing guest console test execution in Mission 012" >&2
  exit 1
fi

echo "OK: plan printed; no QEMU invoked."
exit 0
