#!/usr/bin/env bash
# Build a minimal Ryoku Boot Seed initramfs (Mission 008.5 final fixes).
# DEFAULT: dry-run (no write). Set RYOKU_INITRAMFS_EXECUTE=1 to pack.
#
# Safety:
# - No root/sudo, no host /dev node copies, no network downloads, no disks.
# - /init must be proven static x86_64 ELF via ryoku-virtlab check-static-elf
#   (byte analysis — does NOT use ldd).
# - CPIO includes ./dev/console as char 5:1 via reproducible newc metadata
#   (Rust packer), not mknod on the host.
# - RYOKU_INITRAMFS_ALLOW_DYNAMIC is rejected for real guest prep (always refuse).
# - Stale musl artifacts are not reused if the current musl build fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT_REL="tests/qemu/run/ryoku-boot-seed.cpio.gz"
OUT="$ROOT/$OUT_REL"
EXECUTE="${RYOKU_INITRAMFS_EXECUTE:-0}"
ALLOW_DYNAMIC="${RYOKU_INITRAMFS_ALLOW_DYNAMIC:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_MUSL="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

echo "Ryoku boot-seed initramfs builder"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run, 1=pack)"

if [[ "$ALLOW_DYNAMIC" == "1" ]]; then
  echo "error: RYOKU_INITRAMFS_ALLOW_DYNAMIC=1 is blocked for guest prep." >&2
  echo "  Real T3 packing requires a proven-static musl /init. Structure tests use Rust unit tests." >&2
  exit 1
fi

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would musl-build + static-prove + pack newc (with ./dev/console 5:1) → $OUT_REL"
  echo "  cd zaquion-core"
  echo "  rustup target add $MUSL_TARGET"
  echo "  cargo build -p ryoku-init --release --target $MUSL_TARGET"
  echo "  cargo run -p ryoku-virtlab -- check-static-elf target/${MUSL_TARGET}/release/ryoku-init"
  echo "  RYOKU_INITRAMFS_EXECUTE=1 $0"
  echo "NOTE: Dynamic glibc binaries are refused. No ALLOW_DYNAMIC override for guest packing."
  exit 0
fi

if ! command -v gzip >/dev/null 2>&1; then
  echo "error: gzip not found" >&2
  exit 1
fi

echo "Building ryoku-init for $MUSL_TARGET (required; no stale fallback)…"
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
  # Remove prior musl artifact so a failed rebuild cannot reuse a stale binary.
  rm -f "$BIN_MUSL"
  cargo build -p ryoku-init --release --target "$MUSL_TARGET"
)

if [[ ! -x "$BIN_MUSL" ]]; then
  echo "error: musl ryoku-init missing after build ($BIN_MUSL) — refusing stale/missing binary" >&2
  exit 1
fi

echo "Proving static x86_64 ELF (no ldd)…"
(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_MUSL"
)

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-initramfs.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CPIO_RAW="$WORKDIR/ryoku-boot-seed.cpio"
mkdir -p "$(dirname "$OUT")"

echo "Packing newc via ryoku-virtlab (includes ./dev/console char 5:1 metadata)…"
(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- pack-boot-seed-cpio --init "$BIN_MUSL" --out "$CPIO_RAW"
)

gzip -n -c "$CPIO_RAW" >"$OUT"

# Structure sanity without extracting device nodes onto the host.
python3 - <<'PY' "$CPIO_RAW"
import sys
path = sys.argv[1]
data = open(path, "rb").read()
assert data.startswith(b"070701"), "not newc"
assert b"./init\0" in data or b"init\0" in data, "missing init name"
assert b"./dev/console\0" in data or b"dev/console\0" in data, "missing console name"
print("OK: raw newc contains ./init and ./dev/console name records")
PY

echo "OK: $OUT"
echo "NOTE: Boot seed initramfs — not a Ryoku OS rootfs; T3 needs pinned kernel + authorization."
echo "NOTE: READY marker is emitted by ryoku-init only when guest pid==1."
