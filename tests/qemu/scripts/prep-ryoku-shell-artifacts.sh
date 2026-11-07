#!/usr/bin/env bash
# Prepare musl init+console+shell-preview + DRM modules + ryoku-shell.cpio.gz.
# DEFAULT: dry-run. Set RYOKU_SHELL_PREP_EXECUTE=1 to build/pack/hash.
# Does NOT replace graphics/serial packages. No QEMU. Mission 015.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
OUT="$LAB/run/ryoku-shell.cpio.gz"
SUMS="$LAB/results/ryoku-shell-SHA256SUMS.txt"
MODULES_DIR="$LAB/run/virt-drm-modules"
FETCH_SCRIPT="$LAB/scripts/fetch-virt-drm-modules.sh"
EXECUTE="${RYOKU_SHELL_PREP_EXECUTE:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_INIT="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
BIN_CONSOLE="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-console"
BIN_SHELL="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-shell-preview"

echo "Ryoku shell artifact prep (Mission 015)"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run)"

if [[ "$EXECUTE" != "1" ]]; then
  echo "DRY-RUN: would fetch DRM modules, musl-build, pack shell cpio (+modules), write SUMS"
  echo "  RYOKU_SHELL_PREP_EXECUTE=1 $0"
  exit 0
fi

chmod +x "$FETCH_SCRIPT"
RYOKU_DRM_MODULES_EXECUTE=1 "$FETCH_SCRIPT"
test -f "$MODULES_DIR/kernel/drivers/gpu/drm/virtio/virtio-gpu.ko"

(
  cd "$ROOT/zaquion-core"
  rustup target list --installed 2>/dev/null | grep -qx "$MUSL_TARGET" \
    || { echo "error: install $MUSL_TARGET"; exit 1; }
  cargo build -p ryoku-init -p ryoku-console -p ryoku-shell-preview \
    --release --target "$MUSL_TARGET"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_INIT"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_CONSOLE"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_SHELL"
)

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-shell-cpio.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
CPIO_RAW="$WORKDIR/ryoku-shell.cpio"
mkdir -p "$(dirname "$OUT")" "$LAB/results"

(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- pack-ryoku-shell-cpio \
    --init "$BIN_INIT" \
    --console "$BIN_CONSOLE" \
    --shell-preview "$BIN_SHELL" \
    --modules-dir "$MODULES_DIR" \
    --out "$CPIO_RAW"
)
gzip -n -c "$CPIO_RAW" >"$OUT"

{
  echo "# Ryoku shell preview SHA256SUMS — Mission 015"
  (cd "$ROOT" && sha256sum "tests/qemu/run/ryoku-shell.cpio.gz")
  if [[ -f "$LAB/run/ryoku-boot-seed-vmlinuz" ]]; then
    (cd "$ROOT" && sha256sum "tests/qemu/run/ryoku-boot-seed-vmlinuz")
  fi
  sha256sum "$BIN_INIT" "$BIN_CONSOLE" "$BIN_SHELL"
  cat "$MODULES_DIR/PROVENANCE.txt"
  cat "$MODULES_DIR/SHA256SUMS.txt"
} | tee "$SUMS"

if [[ -f "$LAB/run/ryoku-boot-seed-vmlinuz" ]]; then
  (
    cd "$LAB/run"
    sha256sum ryoku-boot-seed-vmlinuz ryoku-shell.cpio.gz | tee SHA256SUMS-shell.txt
  )
fi

echo "OK: $OUT"
echo "NOTE: does not overwrite ryoku-graphics.cpio.gz / ryoku-minimal.cpio.gz. shell guest NOT_RUN."
