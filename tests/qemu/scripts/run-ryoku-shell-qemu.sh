#!/usr/bin/env bash
# Mission 016.2 — Ryoku Shell + adaptive/controlled-perf QEMU helper (plan-only by default).
# Dual gate: RYOKU_SHELL_QEMU_EXECUTE=1 + RYOKU_SHELL_QEMU_CONFIRM=RUN
# Adds virtio keyboard + tablet so the guest can expose /dev/input/event*.
# Allowlisted host→guest params via kernel cmdline (ryoku.*) — T3 append path unchanged.
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

echo "Ryoku Minimal SHELL QEMU helper (Mission 016.2 controlled-perf)"
echo "  mode:     $MODE"
echo "  package:  $PKG"
echo "  kernel:   $KERNEL"
echo "  initrd:   $INITRD"
echo "  sums:     $SUMS"
echo "  display:  $DISPLAY_BACKEND"
echo "  execute:  $EXECUTE (0=plan/validate; 1 needs CONFIRM=RUN)"
echo "  note:     LAUNCHER_GUEST=NOT_RUN ADAPTIVE_PROFILE=NOT_RUN ADAPTIVE_PERF=NOT_RUN CONTROLLED_BENCHMARK=NOT_RUN GUEST_NOT_RUN until human"
echo "  note:     F1=Lite F2=Balanced F3=Ultra(arch→Balanced); no blur/3D/Wayland claim"
echo "  note:     QEMU TCG ≠ hardware; PERF overlay / controlled benchmark off by default"

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
# Graphical shell profile only: hide fbcon hardware cursor (rest flicker ≠ tearing).
# Serial/T3/minimal packages do NOT set vt.global_cursor_default.
APPEND_CMDLINE="console=ttyS0 vt.global_cursor_default=0"

# Mission 016.2 — allowlisted host→guest params only (init maps ryoku.* → env).
# T3 boot-seed helpers never set these; they stay on console=ttyS0 (+ earlyprintk).
RYOKU_APPEND_EXTRA=()
case "${RYOKU_DESKTOP_PROFILE:-}" in
  lite|balanced|ultra)
    RYOKU_APPEND_EXTRA+=("ryoku.profile=${RYOKU_DESKTOP_PROFILE}")
    ;;
  "") ;;
  *) fail "RYOKU_DESKTOP_PROFILE must be lite|balanced|ultra when set (got ${RYOKU_DESKTOP_PROFILE})" ;;
esac
case "${RYOKU_SHELL_PERF_OVERLAY:-}" in
  1|true|TRUE) RYOKU_APPEND_EXTRA+=("ryoku.perf_overlay=1") ;;
  0|false|FALSE|"") ;;
  *) fail "RYOKU_SHELL_PERF_OVERLAY must be 0|1 when set" ;;
esac
case "${RYOKU_CONTROLLED_BENCHMARK:-}" in
  1|true|TRUE) RYOKU_APPEND_EXTRA+=("ryoku.controlled_benchmark=1") ;;
  0|false|FALSE|"") ;;
  *) fail "RYOKU_CONTROLLED_BENCHMARK must be 0|1 when set" ;;
esac
for tok in "${RYOKU_APPEND_EXTRA[@]+"${RYOKU_APPEND_EXTRA[@]}"}"; do
  APPEND_CMDLINE+=" $tok"
done
if [[ ${#RYOKU_APPEND_EXTRA[@]} -gt 0 ]]; then
  echo "  cmdline+: ${RYOKU_APPEND_EXTRA[*]}"
fi

echo "PLAN (reproducible argv — not executed unless authorized):"
echo "  qemu-system-x86_64 \\"
echo "    -name ryoku-virtlab-shell-input \\"
echo "    -accel tcg -m 256 -smp 1 \\"
echo "    ${DISPLAY_ARGS[*]} -nodefaults -nic none \\"
echo "    -device virtio-vga \\"
echo "    -device virtio-keyboard-pci \\"
echo "    -device virtio-tablet-pci \\"
echo "    -kernel $KERNEL \\"
echo "    -initrd $INITRD \\"
echo "    -append '$APPEND_CMDLINE' \\"
echo "    -serial stdio -monitor none \\"
echo "    -machine type=pc"
echo
echo "Honesty: guest evdev only (not host /dev/input). No Bash/Hyprland/Wayland. No arbitrary app exec."
echo "Honesty: vt.global_cursor_default=0 is fbcon cursor hide (not DRM pageflip / not GTK tear claim)."
echo "Honesty: ryoku.* cmdline keys are allowlisted only; T3 packages omit them."

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

echo "AUTHORIZED: starting QEMU shell+input profile (TCG, nic=none, serial=stdio)…"
exec qemu-system-x86_64 \
  -name ryoku-virtlab-shell-input \
  -accel tcg \
  -m 256 \
  -smp 1 \
  "${DISPLAY_ARGS[@]}" \
  -nodefaults \
  -nic none \
  -device virtio-vga \
  -device virtio-keyboard-pci \
  -device virtio-tablet-pci \
  -kernel "$KERNEL" \
  -initrd "$INITRD" \
  -append "$APPEND_CMDLINE" \
  -serial stdio \
  -monitor none \
  -machine type=pc
