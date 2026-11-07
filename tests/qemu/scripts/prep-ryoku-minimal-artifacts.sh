#!/usr/bin/env bash
# Prepare musl ryoku-init + ryoku-console + Minimal initramfs + SHA256SUMS.
# DEFAULT: dry-run. Set RYOKU_MINIMAL_PREP_EXECUTE=1 to build/pack/hash.
#
# Does NOT: download ISO/kernel, run QEMU, sudo, or overwrite T3 boot-seed.cpio.gz.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
EXECUTE="${RYOKU_MINIMAL_PREP_EXECUTE:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_INIT="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
BIN_CONSOLE="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-console"
INITRD="$LAB/run/ryoku-minimal.cpio.gz"
KERNEL="$LAB/run/ryoku-boot-seed-vmlinuz"
SUMS="$LAB/results/ryoku-minimal-SHA256SUMS.txt"
README_VM="$LAB/results/README-VM.md"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

echo "Ryoku Minimal artifact prep"
echo "  init:     $BIN_INIT"
echo "  console:  $BIN_CONSOLE"
echo "  initrd:   $INITRD"
echo "  sums:     $SUMS"
echo "  execute:  $EXECUTE (0=dry-run, 1=build+pack+hash)"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would musl-build init+console, static-prove, pack Minimal cpio.gz, write SHA256SUMS"
  echo "  RYOKU_MINIMAL_INITRAMFS_EXECUTE=1 tests/qemu/scripts/build-ryoku-minimal-initramfs.sh"
  echo "NOTE: Does not replace T3 ryoku-boot-seed.cpio.gz. No QEMU."
  exit 0
fi

mkdir -p "$LAB/results" "$LAB/run"

RYOKU_MINIMAL_INITRAMFS_EXECUTE=1 "$ROOT/tests/qemu/scripts/build-ryoku-minimal-initramfs.sh"

[[ -x "$BIN_INIT" ]] || { echo "error: musl ryoku-init missing" >&2; exit 1; }
[[ -x "$BIN_CONSOLE" ]] || { echo "error: musl ryoku-console missing" >&2; exit 1; }
[[ -f "$INITRD" ]] || { echo "error: Minimal initrd missing" >&2; exit 1; }

(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_INIT"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_CONSOLE"
)

{
  echo "# Ryoku Minimal SHA256SUMS — Mission 012 FINAL"
  echo "# SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
  echo "# generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Paths relative to repository root."
  echo
  (cd "$ROOT" && sha256sum \
    "zaquion-core/target/${MUSL_TARGET}/release/ryoku-init" \
    "zaquion-core/target/${MUSL_TARGET}/release/ryoku-console" \
    "tests/qemu/run/ryoku-minimal.cpio.gz")
  if [[ -f "$KERNEL" ]]; then
    (cd "$ROOT" && sha256sum "tests/qemu/run/ryoku-boot-seed-vmlinuz")
  else
    echo "# lab kernel not present in this prep step"
  fi
} | tee "$SUMS"

cp -f "$ROOT/tests/qemu/README-VM.md" "$README_VM" 2>/dev/null \
  || cp -f "$ROOT/docs/testing/ryoku-minimal.md" "$README_VM"

echo "OK: Minimal artifacts + $SUMS"
echo "NOTE: Guest interactive boot still requires separate QEMU authorization."
