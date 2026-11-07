#!/usr/bin/env bash
# Mission 011 — dry-run helper for the interactive console QEMU profile.
# DEFAULT: dry-run (print plan only). Never boots QEMU here.
# Does not download ISOs, install packages, or dispatch workflows.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CONF="$ROOT/tests/qemu/configs/console-interactive.rvl.conf"
T3_CONF="$ROOT/tests/qemu/configs/t3-boot-seed.rvl.conf"
EXECUTE="${RYOKU_CONSOLE_INTERACTIVE_EXECUTE:-0}"

echo "Ryoku console interactive prep (Mission 011)"
echo "  config:   $CONF"
echo "  execute:  $EXECUTE (0=dry-run; real guest boot NOT authorized in Mission 011)"

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
if ! grep -q 'serial_log = results/serial-t3-boot-seed.log' "$T3_CONF"; then
  echo "error: T3 file-serial path changed unexpectedly" >&2
  exit 1
fi
if grep -q 'serial_log = stdio' "$T3_CONF"; then
  echo "error: T3 profile must NOT use stdio serial" >&2
  exit 1
fi

echo
echo "DRY-RUN plan:"
echo "  1. Preserve T3 READY/pid1 via ryoku-init (unchanged in Mission 011)"
echo "  2. Host-test: cargo test -p ryoku-console"
echo "  3. Future (separate auth): build guest with console + QEMU -serial stdio"
echo "  4. Never claim product OS boot from console builtins"
echo
echo "NOTE: Mission 011 stops at prep. RYOKU_CONSOLE_INTERACTIVE_EXECUTE=1 is refused."

if [[ "$EXECUTE" == "1" ]]; then
  echo "error: refusing real interactive boot in Mission 011 (no EXECUTE path yet)" >&2
  exit 1
fi

exit 0
