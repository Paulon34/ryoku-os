#!/usr/bin/env bash
# Mission 012.1 — Ryoku Minimal interactive QEMU helper (self-contained ZIP + repo).
# DEFAULT: plan + validate artifacts only. Does NOT start QEMU.
#
# Layouts:
#   standalone — script sits beside kernel/initrd/SHA256SUMS.txt (extracted VM zip)
#   repo       — script under tests/qemu/scripts/; artifacts under tests/qemu/run/
#
# Real guest boot requires ALL of:
#   RYOKU_MINIMAL_QEMU_EXECUTE=1
#   RYOKU_MINIMAL_QEMU_CONFIRM=RUN
#
# Safety: TCG only, -nic none, no physical disks, -display none -serial stdio -monitor none.
# Standalone mode does NOT require T3 files. Does not overwrite T3 boot-seed artifacts.
set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXECUTE="${RYOKU_MINIMAL_QEMU_EXECUTE:-0}"
CONFIRM="${RYOKU_MINIMAL_QEMU_CONFIRM:-}"

MODE=""
PKG=""
KERNEL=""
INITRD=""
SUMS=""
CONF=""
T3_CONF=""

if [[ -f "$SCRIPT_DIR/SHA256SUMS.txt" \
   && -f "$SCRIPT_DIR/ryoku-boot-seed-vmlinuz" \
   && -f "$SCRIPT_DIR/ryoku-minimal.cpio.gz" ]]; then
  MODE="standalone"
  PKG="$SCRIPT_DIR"
  KERNEL="$SCRIPT_DIR/ryoku-boot-seed-vmlinuz"
  INITRD="$SCRIPT_DIR/ryoku-minimal.cpio.gz"
  SUMS="$SCRIPT_DIR/SHA256SUMS.txt"
  CONF="$SCRIPT_DIR/console-interactive.rvl.conf"
elif [[ -d "$SCRIPT_DIR/../../run" ]]; then
  # Repo tree: tests/qemu/scripts → tests/qemu
  MODE="repo"
  local_qemu="$(cd "$SCRIPT_DIR/.." && pwd)"
  PKG="$local_qemu/run"
  KERNEL="$PKG/ryoku-boot-seed-vmlinuz"
  INITRD="$PKG/ryoku-minimal.cpio.gz"
  # Prefer short-name SUMS next to blobs; fall back to staged package dir.
  if [[ -f "$PKG/SHA256SUMS.txt" ]]; then
    SUMS="$PKG/SHA256SUMS.txt"
  elif [[ -f "$local_qemu/results/ryoku-minimal-vm-package/SHA256SUMS.txt" ]]; then
    SUMS="$local_qemu/results/ryoku-minimal-vm-package/SHA256SUMS.txt"
    PKG="$local_qemu/results/ryoku-minimal-vm-package"
    KERNEL="$PKG/ryoku-boot-seed-vmlinuz"
    INITRD="$PKG/ryoku-minimal.cpio.gz"
  else
    SUMS="$PKG/SHA256SUMS.txt" # expected path (will fail check below)
  fi
  CONF="$local_qemu/configs/console-interactive.rvl.conf"
  T3_CONF="$local_qemu/configs/t3-boot-seed.rvl.conf"
else
  fail "cannot detect layout: place script beside ZIP artifacts, or keep it under tests/qemu/scripts/"
fi

echo "Ryoku Minimal QEMU helper (Mission 012.1)"
echo "  mode:     $MODE"
echo "  package:  $PKG"
echo "  kernel:   $KERNEL"
echo "  initrd:   $INITRD"
echo "  sums:     $SUMS"
echo "  execute:  $EXECUTE (0=plan/validate; 1 needs CONFIRM=RUN)"
echo "  confirm:  ${CONFIRM:-(empty)}"

# --- required files ---
[[ -f "$SUMS" ]] || fail "missing SHA256SUMS.txt at $SUMS (required before any run)"
[[ -f "$KERNEL" ]] || fail "missing lab kernel $KERNEL"
[[ -f "$INITRD" ]] || fail "missing Minimal initrd $INITRD"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum not found"

# --- always verify hashes (paths relative to SUMS directory) ---
SUMS_DIR="$(cd "$(dirname "$SUMS")" && pwd)"
echo "Verifying SHA256SUMS.txt …"
(
  cd "$SUMS_DIR"
  # Require the two boot blobs to be listed and match.
  grep -E '[[:space:]]ryoku-boot-seed-vmlinuz$' "$(basename "$SUMS")" >/dev/null \
    || fail "SHA256SUMS.txt missing ryoku-boot-seed-vmlinuz entry"
  grep -E '[[:space:]]ryoku-minimal.cpio.gz$' "$(basename "$SUMS")" >/dev/null \
    || fail "SHA256SUMS.txt missing ryoku-minimal.cpio.gz entry"
  sha256sum -c "$(basename "$SUMS")" --strict
) || fail "SHA256SUMS verification failed"
echo "OK: SHA256SUMS verified"

# --- optional conf sanity (never require T3 in standalone) ---
if [[ -f "$CONF" ]]; then
  grep -q 'serial_log = stdio' "$CONF" || fail "interactive profile must use serial_log=stdio"
  grep -q 'accel = tcg' "$CONF" || fail "must keep accel=tcg"
  grep -q 'network = none' "$CONF" || fail "must keep network=none"
  grep -q 'disk = none' "$CONF" || fail "must keep disk=none"
fi

if [[ "$MODE" == "repo" ]]; then
  [[ -f "$T3_CONF" ]] || fail "repo mode: missing T3 profile $T3_CONF (must stay preserved)"
  grep -q 'serial_log = results/serial-t3-boot-seed.log' "$T3_CONF" || fail "T3 file-serial changed"
  grep -q 'initrd = run/ryoku-boot-seed.cpio.gz' "$T3_CONF" || fail "T3 initrd must stay boot-seed"
  ! grep -q 'ryoku-minimal' "$T3_CONF" || fail "T3 must not point at Minimal initrd"
fi

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

if [[ "$EXECUTE" != "1" ]]; then
  echo "OK: plan+validate only ($MODE). Set RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM=RUN for guest (authorized)."
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
