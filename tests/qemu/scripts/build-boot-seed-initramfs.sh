#!/usr/bin/env bash
# Build a minimal Ryoku Boot Seed initramfs (Mission 008).
# DEFAULT: dry-run (no write). Set RYOKU_INITRAMFS_EXECUTE=1 to pack.
# No root, no host system file copies — only the ryoku-init binary as /init.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT_REL="tests/qemu/run/ryoku-boot-seed.cpio.gz"
OUT="$ROOT/$OUT_REL"
EXECUTE="${RYOKU_INITRAMFS_EXECUTE:-0}"
BIN_RELEASE="$ROOT/zaquion-core/target/release/ryoku-init"
BIN_DEBUG="$ROOT/zaquion-core/target/debug/ryoku-init"
BIN_MUSL="$ROOT/zaquion-core/target/x86_64-unknown-linux-musl/release/ryoku-init"

echo "Ryoku boot-seed initramfs builder"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run, 1=pack)"

pick_bin() {
  if [[ -x "$BIN_MUSL" ]]; then
    echo "$BIN_MUSL"
  elif [[ -x "$BIN_RELEASE" ]]; then
    echo "$BIN_RELEASE"
  elif [[ -x "$BIN_DEBUG" ]]; then
    echo "$BIN_DEBUG"
  else
    return 1
  fi
}

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would cargo-build ryoku-init and pack /init into $OUT_REL"
  echo "  cd zaquion-core && cargo build -p ryoku-init --release"
  echo "  # optional static: --target x86_64-unknown-linux-musl"
  echo "  RYOKU_INITRAMFS_EXECUTE=1 $0"
  exit 0
fi

if ! command -v cpio >/dev/null 2>&1; then
  echo "error: cpio not found" >&2
  exit 1
fi
if ! command -v gzip >/dev/null 2>&1; then
  echo "error: gzip not found" >&2
  exit 1
fi

echo "Building ryoku-init (release)…"
(cd "$ROOT/zaquion-core" && cargo build -p ryoku-init --release)

BIN="$(pick_bin)" || {
  echo "error: ryoku-init binary not found after build" >&2
  exit 1
}
echo "Using binary: $BIN"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-initramfs.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "$WORKDIR/root"
cp -f "$BIN" "$WORKDIR/root/init"
chmod 0755 "$WORKDIR/root/init"

# Structure-only extras (empty dirs help some kernels; no host copies).
mkdir -p "$WORKDIR/root/dev" "$WORKDIR/root/proc" "$WORKDIR/root/sys" "$WORKDIR/root/tmp"

mkdir -p "$(dirname "$OUT")"
(
  cd "$WORKDIR/root"
  find . -print0 | cpio --null --create --format=newc 2>/dev/null | gzip -n >"$OUT"
)

# Sanity: archive non-empty and lists ./init
gzip -dc "$OUT" | cpio -t 2>/dev/null | tee "$WORKDIR/list.txt" | grep -E '^\./init$' >/dev/null
echo "OK: $OUT"
echo "NOTE: Boot seed initramfs — not a Ryoku OS rootfs; T3 needs a pinned kernel + authorization."
