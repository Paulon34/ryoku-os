#!/usr/bin/env bash
# Prepare musl init+console+graphics-demo + ryoku-graphics.cpio.gz + SHA256SUMS.
# DEFAULT: dry-run. Set RYOKU_GRAPHICS_PREP_EXECUTE=1 to build/pack/hash.
# Does NOT replace ryoku-minimal.cpio.gz / serial 013 package. No QEMU.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
OUT="$LAB/run/ryoku-graphics.cpio.gz"
SUMS="$LAB/results/ryoku-graphics-SHA256SUMS.txt"
EXECUTE="${RYOKU_GRAPHICS_PREP_EXECUTE:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_INIT="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
BIN_CONSOLE="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-console"
BIN_GFX="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-graphics-demo"

echo "Ryoku graphics artifact prep (Mission 014)"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run)"

if [[ "$EXECUTE" != "1" ]]; then
  echo "DRY-RUN: would musl-build init+console+graphics-demo, pack graphics cpio, write SUMS"
  echo "  cargo build -p ryoku-init -p ryoku-console -p ryoku-graphics-demo --release --target $MUSL_TARGET"
  echo "  RYOKU_GRAPHICS_PREP_EXECUTE=1 $0"
  exit 0
fi

(
  cd "$ROOT/zaquion-core"
  rustup target list --installed 2>/dev/null | grep -qx "$MUSL_TARGET" \
    || { echo "error: install $MUSL_TARGET"; exit 1; }
  cargo build -p ryoku-init -p ryoku-console -p ryoku-graphics-demo \
    --release --target "$MUSL_TARGET"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_INIT"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_CONSOLE"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_GFX"
)

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-graphics-cpio.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
CPIO_RAW="$WORKDIR/ryoku-graphics.cpio"
mkdir -p "$(dirname "$OUT")" "$LAB/results"

(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- pack-ryoku-graphics-cpio \
    --init "$BIN_INIT" \
    --console "$BIN_CONSOLE" \
    --graphics-demo "$BIN_GFX" \
    --out "$CPIO_RAW"
)
gzip -n -c "$CPIO_RAW" >"$OUT"

{
  echo "# Ryoku graphics preview SHA256SUMS — Mission 014"
  (cd "$ROOT" && sha256sum "tests/qemu/run/ryoku-graphics.cpio.gz")
  if [[ -f "$LAB/run/ryoku-boot-seed-vmlinuz" ]]; then
    (cd "$ROOT" && sha256sum "tests/qemu/run/ryoku-boot-seed-vmlinuz")
  fi
  sha256sum "$BIN_INIT" "$BIN_CONSOLE" "$BIN_GFX"
} | tee "$SUMS"

# Short SUMS next to blobs for launcher (kernel may be shared with Minimal run/).
if [[ -f "$LAB/run/ryoku-boot-seed-vmlinuz" ]]; then
  (
    cd "$LAB/run"
    sha256sum ryoku-boot-seed-vmlinuz ryoku-graphics.cpio.gz | tee SHA256SUMS-graphics.txt
  )
fi

echo "OK: $OUT"
echo "NOTE: does not overwrite ryoku-minimal.cpio.gz. FIRST_PIXELS=NOT_RUN."
