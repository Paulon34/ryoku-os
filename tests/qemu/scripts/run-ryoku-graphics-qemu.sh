#!/usr/bin/env bash
# Mission 014 — Ryoku Minimal graphics QEMU helper (plan-only by default).
# DEFAULT: plan + validate artifacts. Does NOT start QEMU.
#
# Dual gate for execute:
#   RYOKU_GRAPHICS_QEMU_EXECUTE=1
#   RYOKU_GRAPHICS_QEMU_CONFIRM=RUN
#
# Safety: TCG, 256MB, 1 CPU, no net, no disks, serial stdio kept.
# Adds virtio-vga + windowed display (gtk|sdl) — not passthrough / not required 3D.
set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXECUTE="${RYOKU_GRAPHICS_QEMU_EXECUTE:-0}"
CONFIRM="${RYOKU_GRAPHICS_QEMU_CONFIRM:-}"
DISPLAY_BACKEND="${RYOKU_GRAPHICS_DISPLAY:-gtk}"

MODE=""
PKG=""
KERNEL=""
INITRD=""
SUMS=""

if [[ -f "$SCRIPT_DIR/SHA256SUMS.txt" \
   && -f "$SCRIPT_DIR/ryoku-boot-seed-vmlinuz" \
   && -f "$SCRIPT_DIR/ryoku-graphics.cpio.gz" ]]; then
  MODE="standalone"
  PKG="$SCRIPT_DIR"
  KERNEL="$SCRIPT_DIR/ryoku-boot-seed-vmlinuz"
  INITRD="$SCRIPT_DIR/ryoku-graphics.cpio.gz"
  SUMS="$SCRIPT_DIR/SHA256SUMS.txt"
elif [[ -d "$SCRIPT_DIR/../run" ]]; then
  MODE="repo"
  local_qemu="$(cd "$SCRIPT_DIR/.." && pwd)"
  PKG="$local_qemu/run"
  KERNEL="$PKG/ryoku-boot-seed-vmlinuz"
  INITRD="$PKG/ryoku-graphics.cpio.gz"
  if [[ -f "$PKG/SHA256SUMS-graphics.txt" ]]; then
    SUMS="$PKG/SHA256SUMS-graphics.txt"
  elif [[ -f "$local_qemu/results/ryoku-graphics-vm-package/SHA256SUMS.txt" ]]; then
    SUMS="$local_qemu/results/ryoku-graphics-vm-package/SHA256SUMS.txt"
    PKG="$local_qemu/results/ryoku-graphics-vm-package"
    KERNEL="$PKG/ryoku-boot-seed-vmlinuz"
    INITRD="$PKG/ryoku-graphics.cpio.gz"
  else
    SUMS="$PKG/SHA256SUMS-graphics.txt"
  fi
else
  fail "cannot detect layout: place script beside graphics ZIP artifacts, or under tests/qemu/scripts/"
fi

case "$DISPLAY_BACKEND" in
  gtk|sdl|none) ;;
  *) fail "RYOKU_GRAPHICS_DISPLAY must be gtk|sdl|none (got $DISPLAY_BACKEND)" ;;
esac

echo "Ryoku Minimal GRAPHICS QEMU helper (Mission 014)"
echo "  mode:     $MODE"
echo "  package:  $PKG"
echo "  kernel:   $KERNEL"
echo "  initrd:   $INITRD"
echo "  sums:     $SUMS"
echo "  display:  $DISPLAY_BACKEND"
echo "  execute:  $EXECUTE (0=plan/validate; 1 needs CONFIRM=RUN)"
echo "  confirm:  ${CONFIRM:-(empty)}"
echo "  note:     FIRST_PIXELS=NOT_RUN until a human records a visual PASS"

[[ -f "$SUMS" ]] || fail "missing SHA256SUMS at $SUMS"
[[ -f "$KERNEL" ]] || fail "missing lab kernel $KERNEL"
[[ -f "$INITRD" ]] || fail "missing graphics initrd $INITRD"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum not found"

SUMS_DIR="$(cd "$(dirname "$SUMS")" && pwd)"
echo "Verifying SHA256SUMS …"
(
  cd "$SUMS_DIR"
  grep -E '[[:space:]]ryoku-boot-seed-vmlinuz$' "$(basename "$SUMS")" >/dev/null \
    || fail "SHA256SUMS missing ryoku-boot-seed-vmlinuz"
  grep -E '[[:space:]]ryoku-graphics.cpio.gz$' "$(basename "$SUMS")" >/dev/null \
    || fail "SHA256SUMS missing ryoku-graphics.cpio.gz"
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
echo "    -name ryoku-virtlab-console-graphics \\"
echo "    -accel tcg -m 256 -smp 1 \\"
echo "    ${DISPLAY_ARGS[*]} -nodefaults -nic none \\"
echo "    -device virtio-vga \\"
echo "    -kernel $KERNEL \\"
echo "    -initrd $INITRD \\"
echo "    -append 'console=ttyS0' \\"
echo "    -serial stdio -monitor none \\"
echo "    -machine type=pc"
echo
echo "Honesty: virtio-vga PCI ≠ loaded DRM driver. Alpine virt modules not in Minimal cpio."
echo "Status matrix targets: build/package CI; driver inspection via hw graphics; FIRST_PIXELS=NOT_RUN."

if [[ "$EXECUTE" != "1" ]]; then
  echo "OK: plan+validate only ($MODE). Set RYOKU_GRAPHICS_QEMU_EXECUTE=1 RYOKU_GRAPHICS_QEMU_CONFIRM=RUN for guest (authorized)."
  exit 0
fi

if [[ "$CONFIRM" != "RUN" ]]; then
  fail "RYOKU_GRAPHICS_QEMU_EXECUTE=1 requires RYOKU_GRAPHICS_QEMU_CONFIRM=RUN"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  fail "qemu-system-x86_64 not found (install only on disposable authorized runners)"
fi

echo "AUTHORIZED: starting QEMU graphics profile (TCG, nic=none, serial=stdio)…"
exec qemu-system-x86_64 \
  -name ryoku-virtlab-console-graphics \
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
