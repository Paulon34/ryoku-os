#!/usr/bin/env bash
# Build Ryoku Minimal experimental initramfs (Mission 012).
# DEFAULT: dry-run (no write). Set RYOKU_MINIMAL_INITRAMFS_EXECUTE=1 to pack.
#
# Separate from T3 Boot Seed (`build-boot-seed-initramfs.sh`):
#   - ships /bin/ryoku-console + /etc/ryoku-release + /home/ryoku/
#   - output: tests/qemu/run/ryoku-minimal.cpio.gz
#   - does NOT overwrite ryoku-boot-seed.cpio.gz
#
# Safety: no root/sudo, no host /dev copies, no network, no disks.
# Both /init and /bin/ryoku-console must prove static x86_64 musl ELF.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT_REL="tests/qemu/run/ryoku-minimal.cpio.gz"
OUT="$ROOT/$OUT_REL"
T3_OUT="$ROOT/tests/qemu/run/ryoku-boot-seed.cpio.gz"
EXECUTE="${RYOKU_MINIMAL_INITRAMFS_EXECUTE:-0}"
ALLOW_DYNAMIC="${RYOKU_INITRAMFS_ALLOW_DYNAMIC:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_INIT="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
BIN_CONSOLE="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-console"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

echo "Ryoku Minimal initramfs builder (Mission 012)"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run, 1=pack)"
echo "  note:    T3 artifact path remains $T3_OUT (untouched by this script)"

if [[ "$ALLOW_DYNAMIC" == "1" ]]; then
  echo "error: RYOKU_INITRAMFS_ALLOW_DYNAMIC=1 is blocked for guest prep." >&2
  exit 1
fi

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would musl-build init+console + static-prove + pack Minimal newc → $OUT_REL"
  echo "  cd zaquion-core"
  echo "  rustup target add $MUSL_TARGET"
  echo "  cargo build -p ryoku-init -p ryoku-console --release --target $MUSL_TARGET"
  echo "  cargo run -p ryoku-virtlab -- check-static-elf target/${MUSL_TARGET}/release/ryoku-init"
  echo "  cargo run -p ryoku-virtlab -- check-static-elf target/${MUSL_TARGET}/release/ryoku-console"
  echo "  RYOKU_MINIMAL_INITRAMFS_EXECUTE=1 $0"
  echo "NOTE: Does not replace T3 boot-seed initramfs. No QEMU in this script."
  exit 0
fi

if ! command -v gzip >/dev/null 2>&1; then
  echo "error: gzip not found" >&2
  exit 1
fi

echo "Building ryoku-init + ryoku-console for $MUSL_TARGET…"
(
  cd "$ROOT/zaquion-core"
  if ! command -v rustup >/dev/null 2>&1; then
    echo "error: rustup required to build musl target" >&2
    exit 1
  fi
  if ! rustup target list --installed 2>/dev/null | grep -qx "$MUSL_TARGET"; then
    echo "error: $MUSL_TARGET not installed. On a disposable builder: rustup target add $MUSL_TARGET" >&2
    exit 1
  fi
  rm -f "$BIN_INIT" "$BIN_CONSOLE"
  cargo build -p ryoku-init -p ryoku-console --release --target "$MUSL_TARGET"
)

if [[ ! -x "$BIN_INIT" ]]; then
  echo "error: musl ryoku-init missing after build ($BIN_INIT)" >&2
  exit 1
fi
if [[ ! -x "$BIN_CONSOLE" ]]; then
  echo "error: musl ryoku-console missing after build ($BIN_CONSOLE)" >&2
  exit 1
fi

echo "Proving static x86_64 ELF (no ldd)…"
(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_INIT"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_CONSOLE"
)

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-minimal-initramfs.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CPIO_RAW="$WORKDIR/ryoku-minimal.cpio"
mkdir -p "$(dirname "$OUT")"

echo "Packing Minimal newc via ryoku-virtlab…"
(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- pack-ryoku-minimal-cpio \
    --init "$BIN_INIT" \
    --console "$BIN_CONSOLE" \
    --out "$CPIO_RAW"
)

gzip -n -c "$CPIO_RAW" >"$OUT"

python3 - <<'PY' "$CPIO_RAW"
import sys
path = sys.argv[1]
data = open(path, "rb").read()
assert data.startswith(b"070701"), "not newc"
assert b"./init\0" in data, "missing init"
assert b"./bin/ryoku-console\0" in data, "missing console bin"
assert b"./dev/console\0" in data, "missing console device"
assert b"./etc/ryoku-release\0" in data, "missing release"
assert b"./home/ryoku\0" in data, "missing home"
print("OK: Minimal newc contains required members")
PY

echo "OK: $OUT"
echo "NOTE: Ryoku Minimal — not a product OS rootfs; interactive ≠ T3 evidence."
echo "NOTE: READY marker still emitted only by ryoku-init when guest pid==1."
