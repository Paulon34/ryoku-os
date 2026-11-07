#!/usr/bin/env bash
# Build a minimal Ryoku Boot Seed initramfs (Mission 008 / 008.5).
# DEFAULT: dry-run (no write). Set RYOKU_INITRAMFS_EXECUTE=1 to pack.
# No root/sudo, no host system file copies — only the ryoku-init binary as /init.
# No network downloads. No physical disks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT_REL="tests/qemu/run/ryoku-boot-seed.cpio.gz"
OUT="$ROOT/$OUT_REL"
EXECUTE="${RYOKU_INITRAMFS_EXECUTE:-0}"
ALLOW_DYNAMIC="${RYOKU_INITRAMFS_ALLOW_DYNAMIC:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_RELEASE="$ROOT/zaquion-core/target/release/ryoku-init"
BIN_DEBUG="$ROOT/zaquion-core/target/debug/ryoku-init"
BIN_MUSL="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
# Controlled metadata for reproducible packing (when execute=1).
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

echo "Ryoku boot-seed initramfs builder"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run, 1=pack)"
echo "  allow_dynamic: $ALLOW_DYNAMIC (0=refuse dynamically linked /init)"

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

# True when the ELF needs a dynamic loader (unsafe for bare initramfs).
is_dynamically_linked() {
  local bin="$1"
  if command -v ldd >/dev/null 2>&1; then
    # ldd prints "not a dynamic executable" / "statically linked" for static bins.
    if ldd "$bin" 2>&1 | grep -Eqi 'not a dynamic executable|statically linked'; then
      return 1
    fi
    # Any "=>" dependency means dynamic.
    if ldd "$bin" 2>&1 | grep -q '=>'; then
      return 0
    fi
  fi
  if command -v readelf >/dev/null 2>&1; then
    if readelf -l "$bin" 2>/dev/null | grep -q 'Requesting program interpreter'; then
      return 0
    fi
    return 1
  fi
  # Cannot prove static — treat as dynamic (fail-closed) unless overridden.
  return 0
}

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would build (prefer musl static) and pack /init into $OUT_REL"
  echo "  cd zaquion-core"
  echo "  rustup target add $MUSL_TARGET   # when available"
  echo "  cargo build -p ryoku-init --release --target $MUSL_TARGET"
  echo "  # fallback structure-only (NOT for real T3 guest): cargo build -p ryoku-init --release"
  echo "  RYOKU_INITRAMFS_EXECUTE=1 $0"
  echo "NOTE: Real T3 guest requires a statically linked /init (musl). Dynamic gnu will be refused."
  exit 0
fi

if ! command -v cpio >/dev/null 2>&1; then
  echo "error: cpio not found (needed only for authorized packing)" >&2
  exit 1
fi
if ! command -v gzip >/dev/null 2>&1; then
  echo "error: gzip not found" >&2
  exit 1
fi

echo "Building ryoku-init (prefer musl static)…"
(
  cd "$ROOT/zaquion-core"
  if command -v rustup >/dev/null 2>&1 && rustup target list --installed 2>/dev/null | grep -qx "$MUSL_TARGET"; then
    cargo build -p ryoku-init --release --target "$MUSL_TARGET" || {
      echo "warning: musl target build failed; will evaluate fallback binary" >&2
    }
  elif command -v rustup >/dev/null 2>&1; then
    echo "note: $MUSL_TARGET not installed (rustup target add $MUSL_TARGET + musl linker on a disposable builder)"
  fi
  # Always produce a host release binary for local structure experiments.
  cargo build -p ryoku-init --release
)

BIN="$(pick_bin)" || {
  echo "error: ryoku-init binary not found after build" >&2
  exit 1
}
echo "Using binary: $BIN"

if is_dynamically_linked "$BIN"; then
  if [[ "$ALLOW_DYNAMIC" != "1" ]]; then
    echo "error: refusing dynamically linked /init for initramfs (guest has no glibc/ld-linux)." >&2
    echo "  Build static: rustup target add $MUSL_TARGET && cargo build -p ryoku-init --release --target $MUSL_TARGET" >&2
    echo "  Or set RYOKU_INITRAMFS_ALLOW_DYNAMIC=1 only for host structure tests (NOT real T3)." >&2
    exit 1
  fi
  echo "warning: packing dynamically linked binary (ALLOW_DYNAMIC=1) — NOT suitable for real T3 guest"
else
  echo "OK: binary appears statically linked (or no dynamic interpreter)"
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-initramfs.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "$WORKDIR/root"
# Controlled copy: only our binary → ./init (mode 0755). No host /lib, /bin, disks.
cp -f "$BIN" "$WORKDIR/root/init"
chmod 0755 "$WORKDIR/root/init"
# Normalize mtime for more reproducible archives.
touch -d "@${SOURCE_DATE_EPOCH}" "$WORKDIR/root/init" 2>/dev/null || true

# Empty dirs only (no device nodes without root; virt kernels usually mount devtmpfs).
mkdir -p "$WORKDIR/root/dev" "$WORKDIR/root/proc" "$WORKDIR/root/sys" "$WORKDIR/root/tmp"
touch -d "@${SOURCE_DATE_EPOCH}" \
  "$WORKDIR/root/dev" "$WORKDIR/root/proc" "$WORKDIR/root/sys" "$WORKDIR/root/tmp" 2>/dev/null || true

mkdir -p "$(dirname "$OUT")"
(
  cd "$WORKDIR/root"
  # Sorted find → more stable member order.
  find . -print0 | LC_ALL=C sort -z | cpio --null --create --format=newc --owner=0:0 2>/dev/null \
    | gzip -n >"$OUT"
)

# Sanity: archive non-empty and lists ./init
gzip -dc "$OUT" | cpio -t 2>/dev/null | tee "$WORKDIR/list.txt" | grep -E '^\./init$' >/dev/null
# Permissions: newc mode for regular file should be executable (0755).
echo "OK: $OUT"
echo "NOTE: Boot seed initramfs — not a Ryoku OS rootfs; T3 needs a pinned kernel + authorization."
echo "NOTE: Guest console needs kernel cmdline console=ttyS0 (+ typically CONFIG_DEVTMPFS)."
