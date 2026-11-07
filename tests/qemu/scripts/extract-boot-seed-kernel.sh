#!/usr/bin/env bash
# Extract boot/vmlinuz-virt from a verified Alpine virt ISO into the lab run/ tree.
# DEFAULT: dry-run (no write, no network). Set RYOKU_KERNEL_EXTRACT_EXECUTE=1 to extract.
#
# Safety (Mission 009.5 hardening):
# - No sudo, no mount/losetup of host block devices.
# - Real extract REQUIRES RYOKU_VERIFY_GPG=1 (SHA pin + fingerprint GPG); .asc presence ≠ valid sig.
# - ISO must canonicalize under tests/qemu/run/; refuse dest symlink / out-of-lab paths.
# - Does NOT download the ISO (use fetch-reference-image.sh under separate auth).
# - Alpine kernel reuse ≠ adopting Alpine as Ryoku base (ADR-0002).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
RUN_DIR="$LAB/run"
ISO_NAME="alpine-virt-3.21.9-x86_64.iso"
ISO="$RUN_DIR/$ISO_NAME"
OUT_REL="tests/qemu/run/ryoku-boot-seed-vmlinuz"
OUT="$ROOT/$OUT_REL"
MEMBER="boot/vmlinuz-virt"
EXPECTED_SHA256="1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4"
FP="0482D84022F52DF1C4E7CD43293ACD0907D9495A"
EXECUTE="${RYOKU_KERNEL_EXTRACT_EXECUTE:-0}"
VERIFY_GPG="${RYOKU_VERIFY_GPG:-1}"

echo "Ryoku boot-seed kernel extract"
echo "  iso:     $ISO"
echo "  member:  $MEMBER"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run, 1=extract)"
echo "  verify_gpg: $VERIFY_GPG (must be 1 for real extract)"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would SHA-pin + GPG-verify fingerprint $FP, then extract $MEMBER → $OUT_REL"
  echo "  # ISO must already exist (authorized fetch; no download in this script):"
  echo "  RYOKU_FETCH_EXECUTE=1 tests/qemu/scripts/fetch-reference-image.sh"
  echo "  # Extract (GPG mandatory):"
  echo "  RYOKU_KERNEL_EXTRACT_EXECUTE=1 RYOKU_VERIFY_GPG=1 $0"
  echo "  # Tools on disposable runner: isoinfo / xorriso (no host disk mounts)"
  echo "NOTE: Dry-run performs no network, no extract, no writes. Alpine ≠ Ryoku base."
  exit 0
fi

# Real extract is fail-closed on GPG — presence of .asc alone is never enough.
if [[ "$VERIFY_GPG" != "1" ]]; then
  echo "error: refusing real extract unless RYOKU_VERIFY_GPG=1 (SHA pin + fingerprint GPG required)" >&2
  exit 1
fi

if [[ ! -f "$ISO" ]]; then
  echo "error: ISO missing at $ISO (fetch under separate authorization first)" >&2
  exit 1
fi

# Canonical path: ISO must resolve under tests/qemu/run/ (no escapes / host disks).
RUN_CANON="$(cd "$RUN_DIR" && pwd -P)"
ISO_CANON="$(cd "$(dirname "$ISO")" && pwd -P)/$(basename "$ISO")"
case "$ISO_CANON" in
  "$RUN_CANON"/*) ;;
  *)
    echo "error: ISO canonical path must be under $RUN_CANON (got $ISO_CANON)" >&2
    exit 1
    ;;
esac
# Refuse if ISO itself is a symlink escaping lab (parent already checked; also reject symlink ISO
# whose ultimate target leaves run/).
if [[ -L "$ISO" ]]; then
  ISO_TARGET="$(readlink -f "$ISO" 2>/dev/null || true)"
  case "$ISO_TARGET" in
    "$RUN_CANON"/*) ;;
    *)
      echo "error: ISO symlink resolves outside lab run/: $ISO -> $ISO_TARGET" >&2
      exit 1
      ;;
  esac
fi

# Destination: refuse existing symlink; ensure parent stays in lab run/.
if [[ -L "$OUT" ]]; then
  echo "error: refusing destination symlink $OUT (write only a regular lab file)" >&2
  exit 1
fi
mkdir -p "$RUN_DIR" "$LAB/results"
OUT_PARENT_CANON="$(cd "$(dirname "$OUT")" && pwd -P)"
case "$OUT_PARENT_CANON" in
  "$RUN_CANON") ;;
  *)
    echo "error: destination parent outside lab run/: $OUT_PARENT_CANON" >&2
    exit 1
    ;;
esac
case "$OUT" in
  /dev/*|/proc/*|/sys/*)
    echo "error: refusing dangerous output path: $OUT" >&2
    exit 1
    ;;
esac

SHA_SIDE="$ISO.sha256"
ASC_SIDE="$ISO.asc"
KEY_ASC="$RUN_DIR/ncopa.asc"
if [[ ! -f "$SHA_SIDE" ]]; then
  echo "error: missing SHA sidecar $SHA_SIDE — authorized fetch first" >&2
  exit 1
fi
if [[ ! -f "$ASC_SIDE" ]]; then
  echo "error: missing GPG sidecar $ASC_SIDE — authorized fetch first" >&2
  exit 1
fi
if [[ ! -f "$KEY_ASC" ]]; then
  echo "error: missing ncopa key $KEY_ASC — authorized fetch first" >&2
  exit 1
fi
if ! grep -q "$EXPECTED_SHA256" "$SHA_SIDE"; then
  echo "error: SHA sidecar does not list pinned digest $EXPECTED_SHA256" >&2
  exit 1
fi

echo "Verifying ISO SHA-256 (pin)…"
got="$(sha256sum "$ISO" | awk '{print $1}')"
if [[ "$got" != "$EXPECTED_SHA256" ]]; then
  echo "error: ISO sha256 mismatch (got $got expected $EXPECTED_SHA256)" >&2
  exit 1
fi
echo "OK: ISO sha256 matches pin"

if ! command -v gpg >/dev/null 2>&1; then
  echo "error: gpg not found (required when RYOKU_VERIFY_GPG=1)" >&2
  exit 1
fi

GNUPGHOME="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-gpg.XXXXXX")"
gpg_status="$(mktemp "${TMPDIR:-/tmp}/ryoku-gpg-status.XXXXXX")"
cleanup_gpg() { rm -rf "$GNUPGHOME" "$gpg_status"; }
trap cleanup_gpg EXIT
export GNUPGHOME

echo "Importing ncopa key (fail-closed)…"
if ! gpg --batch --status-fd 1 --import "$KEY_ASC" >"$gpg_status" 2>/dev/null; then
  echo "error: GPG key import failed" >&2
  cat "$gpg_status" >&2 || true
  exit 1
fi
if ! grep -q '\[GNUPG:\] IMPORT_OK' "$gpg_status" && ! grep -q '\[GNUPG:\] IMPORT_OK' <<<"$(cat "$gpg_status")"; then
  # Some gpg versions only print to stderr; re-check imported fingerprint presence.
  if ! gpg --batch --fingerprint "$FP" >/dev/null 2>&1; then
    echo "error: GPG import did not yield expected fingerprint $FP" >&2
    cat "$gpg_status" >&2 || true
    exit 1
  fi
fi

echo "Verifying detached signature (GOODSIG + VALIDSIG $FP)…"
: >"$gpg_status"
gpg_rc=0
gpg --batch --status-fd 1 --verify "$ASC_SIDE" "$ISO" >"$gpg_status" 2>/dev/null || gpg_rc=$?
status="$(cat "$gpg_status" 2>/dev/null || true)"
if [[ "$gpg_rc" -ne 0 ]] || ! grep -q '\[GNUPG:\] GOODSIG' <<<"$status"; then
  echo "error: GPG verify failed — .asc presence is not enough (need exit 0 + GOODSIG)" >&2
  echo "$status" >&2
  exit 1
fi
if ! grep -E "\[GNUPG:\] VALIDSIG ${FP}" <<<"$status" >/dev/null; then
  echo "error: GPG VALIDSIG fingerprint mismatch (want $FP)" >&2
  echo "$status" >&2
  exit 1
fi
echo "OK: GPG GOODSIG + VALIDSIG fingerprint $FP"

# Drop GPG temp before extract workdir.
cleanup_gpg
trap - EXIT

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-kernel-extract.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

extract_ok=0
if command -v isoinfo >/dev/null 2>&1; then
  if isoinfo -R -i "$ISO" -x "/$MEMBER" >"$WORKDIR/vmlinuz" 2>/dev/null \
    && [[ -s "$WORKDIR/vmlinuz" ]]; then
    extract_ok=1
    echo "extracted via isoinfo"
  fi
fi

if [[ "$extract_ok" != "1" ]] && command -v xorriso >/dev/null 2>&1; then
  mkdir -p "$WORKDIR/iso"
  if xorriso -osirrox on -indev "$ISO" -extract "/$MEMBER" "$WORKDIR/iso/vmlinuz" 2>/dev/null \
    && [[ -s "$WORKDIR/iso/vmlinuz" ]]; then
    cp -f "$WORKDIR/iso/vmlinuz" "$WORKDIR/vmlinuz"
    extract_ok=1
    echo "extracted via xorriso"
  fi
fi

if [[ "$extract_ok" != "1" ]]; then
  echo "error: need isoinfo or xorriso on the disposable builder to extract without mount" >&2
  exit 1
fi

# Final dest check immediately before write (TOCTOU-ish guard).
if [[ -L "$OUT" ]]; then
  echo "error: destination became a symlink; refusing write" >&2
  exit 1
fi
cp -f "$WORKDIR/vmlinuz" "$OUT"
chmod 0644 "$OUT"
# Confirm written file still under lab run/.
OUT_CANON="$(cd "$(dirname "$OUT")" && pwd -P)/$(basename "$OUT")"
case "$OUT_CANON" in
  "$RUN_CANON"/*) ;;
  *)
    echo "error: written output escaped lab run/: $OUT_CANON" >&2
    rm -f "$OUT"
    exit 1
    ;;
esac

sha256sum "$OUT" | tee "$LAB/results/boot-seed-kernel.sha256"
echo "OK: $OUT"
echo "NOTE: Kernel extracted for lab T3 only — not a Ryoku product kernel claim."
