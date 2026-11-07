#!/usr/bin/env bash
# Mission 015 — Ryoku Shell Preview QEMU helper (plan-only by default).
# Dual gate: RYOKU_SHELL_QEMU_EXECUTE=1 + RYOKU_SHELL_QEMU_CONFIRM=RUN
set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXECUTE="${RYOKU_SHELL_QEMU_EXECUTE:-0}"
CONFIRM="${RYOKU_SHELL_QEMU_CONFIRM:-}"
DISPLAY_BACKEND="${RYOKU_SHELL_DISPLAY:-gtk}"

MODE=""
PKG=""
KERNEL=""
INITRD=""
SUMS=""

if [[ -f "$SCRIPT_DIR/SHA256SUMS.txt" \
   && -f "$SCRIPT_DIR/ryoku-boot-seed-vmlinuz" \
   && -f "$SCRIPT_DIR/ryoku-shell.cpio.gz" ]]; then
  MODE="standalone"
  PKG="$SCRIPT_DIR"
  KERNEL="$SCRIPT_DIR/ryoku-boot-seed-vmlinuz"
  INITRD="$SCRIPT_DIR/ryoku-shell.cpio.gz"
  SUMS="$SCRIPT_DIR/SHA256SUMS.txt"
elif [[ -d "$SCRIPT_DIR/../run" ]]; then
  MODE="repo"
  local_qemu="$(cd "$SCRIPT_DIR/.." && pwd)"
  PKG="$local_qemu/run"
  KERNEL="$PKG/ryoku-boot-seed-vmlinuz"
  INITRD="$PKG/ryoku-shell.cpio.gz"
  if [[ -f "$PKG/SHA256SUMS-shell.txt" ]]; then
    SUMS="$PKG/SHA256SUMS-shell.txt"
  elif [[ -f "$local_qemu/results/ryoku-shell-vm-package/SHA256SUMS.txt" ]]; then
    SUMS="$local_qemu/results/ryoku-shell-vm-package/SHA256SUMS.txt"
    PKG="$local_qemu/results/ryoku-shell-vm-package"
    KERNEL="$PKG/ryoku-boot-seed-vmlinuz"
    INITRD="$PKG/ryoku-shell.cpio.gz"
  else
    SUMS="$PKG/SHA256SUMS-shell.txt"
  fi
else
  fail "cannot detect layout: place script beside shell ZIP artifacts, or under tests/qemu/scripts/"
fi

case "$DISPLAY_BACKEND" in
  gtk|sdl|none) ;;
  *) fail "RYOKU_SHELL_DISPLAY must be gtk|sdl|none (got $DISPLAY_BACKEND)" ;;
esac

echo "Ryoku Minimal SHELL QEMU helper (Mission 015)"
echo "  mode:     $MODE"
echo "  package:  $PKG"
echo "  kernel:   $KERNEL"
echo "  initrd:   $INITRD"
echo "  sums:     $SUMS"
echo "  display:  $DISPLAY_BACKEND"
echo "  execute:  $EXECUTE (0=plan/validate; 1 needs CONFIRM=RUN)"
echo "  note:     shell graphical guest=NOT_RUN until human visual confirm; input=NOT_RUN (015.1)"

[[ -f "$SUMS" ]] || fail "missing SHA256SUMS at $SUMS"
[[ -f "$KERNEL" ]] || fail "missing lab kernel $KERNEL"
[[ -f "$INITRD" ]] || fail "missing shell initrd $INITRD"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum not found"

SUMS_DIR="$(cd "$(dirname "$SUMS")" && pwd)"
echo "Verifying SHA256SUMS …"
(
  cd "$SUMS_DIR"
  grep -E '[[:space:]]ryoku-boot-seed-vmlinuz$' "$(basename "$SUMS")" >/dev/null \
    || fail "SHA256SUMS missing ryoku-boot-seed-vmlinuz"
  grep -E '[[:space:]]ryoku-shell.cpio.gz$' "$(basename "$SUMS")" >/dev/null \
    || fail "SHA256SUMS missing ryoku-shell.cpio.gz"
  sha256sum -c "$(basename "$SUMS")" --strict
) || fail "SHA256SUMS verification failed"
echo "OK: SHA256SUMS verified"

DISPLAY_ARGS=()
case "$DISPLAY_BACKEND" in
  gtk) DISPLAY_ARGS=(-display gtk,gl=off) ;;
  sdl) DISPLAY_ARGS=(-display sdl,gl=off) ;;
  none) DISPLAY_ARGS=(-display none) ;;
esac

echo
echo "PLAN (reproducible argv — not executed unless authorized):"
echo "  qemu-system-x86_64 \\"
echo "    -name ryoku-virtlab-shell-preview \\"
echo "    -accel tcg -m 256 -smp 1 \\"
echo "    ${DISPLAY_ARGS[*]} -nodefaults -nic none \\"
echo "    -device virtio-vga \\"
echo "    -kernel $KERNEL \\"
echo "    -initrd $INITRD \\"
echo "    -append 'console=ttyS0' \\"
echo "    -serial stdio -monitor none \\"
echo "    -machine type=pc"
echo
echo "Honesty: shell package ships ryoku-shell-preview (not graphics-demo). FIRST_PIXELS preserved on 014 package."

if [[ "$EXECUTE" != "1" ]]; then
  echo "OK: plan+validate only ($MODE). Set RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN for guest (authorized)."
  exit 0
fi

if [[ "$CONFIRM" != "RUN" ]]; then
  fail "RYOKU_SHELL_QEMU_EXECUTE=1 requires RYOKU_SHELL_QEMU_CONFIRM=RUN"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  fail "qemu-system-x86_64 not found"
fi

echo "AUTHORIZED: starting QEMU shell profile (TCG, nic=none, serial=stdio)…"
exec qemu-system-x86_64 \
  -name ryoku-virtlab-shell-preview \
  -accel tcg \
  -m 256 \
  -smp 1 \
  "${DISPLAY_ARGS[@]}" \
  -nodefaults \
  -nic none \
  -device virtio-vga \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "console=ttyS0" \
  -serial stdio \
  -monitor none \
  -machine type=pc
