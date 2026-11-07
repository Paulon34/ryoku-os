#!/usr/bin/env bash
# Prepare ryoku-init (musl) + initramfs artifacts and record hashes (Mission 009).
# DEFAULT: dry-run. Set RYOKU_BOOT_SEED_PREP_EXECUTE=1 to build/pack/hash.
#
# Does NOT: download ISO/kernel, run QEMU/T3, sudo, or install host packages.
# Static ELF proof + CPIO validation via ryoku-virtlab helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
EXECUTE="${RYOKU_BOOT_SEED_PREP_EXECUTE:-0}"
MUSL_TARGET="x86_64-unknown-linux-musl"
BIN_MUSL="$ROOT/zaquion-core/target/${MUSL_TARGET}/release/ryoku-init"
INITRD="$LAB/run/ryoku-boot-seed.cpio.gz"
HASHES="$LAB/results/boot-seed-artifact-hashes.txt"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

echo "Ryoku boot-seed artifact prep"
echo "  musl_bin: $BIN_MUSL"
echo "  initrd:   $INITRD"
echo "  hashes:   $HASHES"
echo "  execute:  $EXECUTE (0=dry-run, 1=build+pack+hash)"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would"
  echo "  1) cargo build -p ryoku-init --release --target $MUSL_TARGET"
  echo "  2) cargo run -p ryoku-virtlab -- check-static-elf <musl bin>  # PT_LOAD + no INTERP/NEEDED"
  echo "  3) RYOKU_INITRAMFS_EXECUTE=1 tests/qemu/scripts/build-boot-seed-initramfs.sh"
  echo "  4) validate CPIO (./init exec + ./dev/console 5:1) via packer checks"
  echo "  5) write sha256 of musl /init and initrd to $HASHES"
  echo "NOTE: Cursor host typically lacks musl — run execute on disposable Ubuntu builder."
  echo "NOTE: Does not run T3 / QEMU. Set RYOKU_T3_EXECUTE=1 only under authorized workflow."
  exit 0
fi

mkdir -p "$LAB/results" "$LAB/run"

echo "Building + packing via initramfs script (musl required)…"
RYOKU_INITRAMFS_EXECUTE=1 "$ROOT/tests/qemu/scripts/build-boot-seed-initramfs.sh"

if [[ ! -x "$BIN_MUSL" ]]; then
  echo "error: musl ryoku-init missing after pack" >&2
  exit 1
fi
if [[ ! -f "$INITRD" ]]; then
  echo "error: initrd missing after pack" >&2
  exit 1
fi

# Re-prove static (packer already did; record for evidence).
(
  cd "$ROOT/zaquion-core"
  cargo run -q -p ryoku-virtlab -- check-static-elf "$BIN_MUSL"
)

{
  echo "# Boot Seed artifact hashes — Mission 009 prep"
  echo "# SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
  echo "# generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## ryoku-init (musl static)"
  sha256sum "$BIN_MUSL"
  echo
  echo "## initramfs (cpio.gz)"
  sha256sum "$INITRD"
  if [[ -f "$LAB/run/ryoku-boot-seed-vmlinuz" ]]; then
    echo
    echo "## lab kernel (if extracted)"
    sha256sum "$LAB/run/ryoku-boot-seed-vmlinuz"
  else
    echo
    echo "## lab kernel"
    echo "(not present — extract via extract-boot-seed-kernel.sh under authorization)"
  fi
} | tee "$HASHES"

echo "OK: hashes → $HASHES"
echo "NOTE: Artifact prep ≠ T3 guest PASS. Guest still needs RYOKU_T3_EXECUTE=1 + QEMU."
