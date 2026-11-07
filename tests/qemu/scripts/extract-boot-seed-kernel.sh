#!/usr/bin/env bash
# Extract boot/vmlinuz-virt from a verified Alpine virt ISO into the lab run/ tree.
# DEFAULT: dry-run (no write, no network). Set RYOKU_KERNEL_EXTRACT_EXECUTE=1 to extract.
#
# Safety (Mission 009):
# - No sudo, no mount of host block devices, no loop-mount of arbitrary disks.
# - Reads only a file under tests/qemu/run/ (lab ISO path).
# - Writes only to tests/qemu/run/ryoku-boot-seed-vmlinuz (gitignored).
# - Does NOT download the ISO (use fetch-reference-image.sh under separate auth).
# - Alpine kernel reuse ≠ adopting Alpine as Ryoku base (ADR-0002).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
ISO_NAME="alpine-virt-3.21.9-x86_64.iso"
ISO="$LAB/run/$ISO_NAME"
OUT_REL="tests/qemu/run/ryoku-boot-seed-vmlinuz"
OUT="$ROOT/$OUT_REL"
MEMBER="boot/vmlinuz-virt"
EXPECTED_SHA256="1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4"
EXECUTE="${RYOKU_KERNEL_EXTRACT_EXECUTE:-0}"

echo "Ryoku boot-seed kernel extract"
echo "  iso:     $ISO"
echo "  member:  $MEMBER"
echo "  out:     $OUT"
echo "  execute: $EXECUTE (0=dry-run, 1=extract)"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: would verify ISO SHA-256 ($EXPECTED_SHA256), then extract $MEMBER → $OUT_REL"
  echo "  # ISO must already exist (authorized fetch):"
  echo "  RYOKU_FETCH_EXECUTE=1 tests/qemu/scripts/fetch-reference-image.sh"
  echo "  # Extract without mounting host disks:"
  echo "  RYOKU_KERNEL_EXTRACT_EXECUTE=1 $0"
  echo "  # Preferred tools (disposable runner): isoinfo -R -x /$MEMBER  OR  xorriso -osirrox on -extract"
  echo "NOTE: Mission 009 does not download ISO/kernel on Cursor. Alpine ≠ Ryoku base."
  exit 0
fi

if [[ ! -f "$ISO" ]]; then
  echo "error: ISO missing at $ISO (fetch under separate authorization first)" >&2
  exit 1
fi

# Lab-path only: ISO must live under tests/qemu/run/ (no host disk / escape paths).
case "$ISO" in
  "$LAB/run/"*) ;;
  *)
    echo "error: ISO path must be under $LAB/run/ (got $ISO)" >&2
    exit 1
    ;;
esac
case "$OUT" in
  "$LAB/run/"*) ;;
  /dev/*|/proc/*|/sys/*|*/../*)
    echo "error: refusing dangerous output path: $OUT" >&2
    exit 1
    ;;
  *)
    echo "error: output must be under $LAB/run/ (got $OUT)" >&2
    exit 1
    ;;
esac

# Integrity first: require fetch sidecars (SHA listing + detached GPG) before extract.
SHA_SIDE="$ISO.sha256"
ASC_SIDE="$ISO.asc"
if [[ ! -f "$SHA_SIDE" ]]; then
  echo "error: missing SHA sidecar $SHA_SIDE — run authorized fetch (SHA+GPG) first" >&2
  exit 1
fi
if [[ ! -f "$ASC_SIDE" ]]; then
  echo "error: missing GPG sidecar $ASC_SIDE — run authorized fetch (SHA+GPG) first" >&2
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
echo "OK: ISO sha256 matches pin; SHA+GPG sidecars present from authorized fetch"

# Optional re-verify of detached signature when gpg is available (fail-closed if requested).
VERIFY_GPG="${RYOKU_VERIFY_GPG:-1}"
if [[ "$VERIFY_GPG" == "1" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "error: gpg not found but RYOKU_VERIFY_GPG=1" >&2
    exit 1
  fi
  KEY_ASC="$LAB/run/ncopa.asc"
  FP="0482D84022F52DF1C4E7CD43293ACD0907D9495A"
  if [[ ! -f "$KEY_ASC" ]]; then
    echo "error: missing ncopa key $KEY_ASC from authorized fetch" >&2
    exit 1
  fi
  GNUPGHOME="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-gpg.XXXXXX")"
  export GNUPGHOME
  gpg --batch --import "$KEY_ASC" >/dev/null 2>&1 || true
  gpg_status="$(mktemp "${TMPDIR:-/tmp}/ryoku-gpg-status.XXXXXX")"
  gpg_rc=0
  gpg --batch --status-fd 1 --verify "$ASC_SIDE" "$ISO" >"$gpg_status" 2>/dev/null || gpg_rc=$?
  status="$(cat "$gpg_status" 2>/dev/null || true)"
  rm -rf "$GNUPGHOME" "$gpg_status"
  unset GNUPGHOME
  if [[ "$gpg_rc" -ne 0 ]] || ! grep -q '\[GNUPG:\] GOODSIG' <<<"$status"; then
    echo "error: GPG verify failed (need exit 0 + GOODSIG)" >&2
    echo "$status" >&2
    exit 1
  fi
  if ! grep -E "\[GNUPG:\] VALIDSIG ${FP}" <<<"$status" >/dev/null; then
    echo "error: GPG VALIDSIG fingerprint mismatch (want $FP)" >&2
    echo "$status" >&2
    exit 1
  fi
  echo "OK: GPG GOODSIG + VALIDSIG fingerprint $FP"
fi

mkdir -p "$(dirname "$OUT")" "$LAB/results"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-kernel-extract.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

extract_ok=0
if command -v isoinfo >/dev/null 2>&1; then
  # Rock Ridge path; leading slash required by isoinfo -x
  if isoinfo -R -i "$ISO" -x "/$MEMBER" >"$WORKDIR/vmlinuz" 2>/dev/null \
    && [[ -s "$WORKDIR/vmlinuz" ]]; then
    extract_ok=1
    echo "extracted via isoinfo"
  fi
fi

if [[ "$extract_ok" != "1" ]] && command -v xorriso >/dev/null 2>&1; then
  mkdir -p "$WORKDIR/iso"
  # Extract single member without mounting host disks.
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

cp -f "$WORKDIR/vmlinuz" "$OUT"
chmod 0644 "$OUT"
sha256sum "$OUT" | tee "$LAB/results/boot-seed-kernel.sha256"
echo "OK: $OUT"
echo "NOTE: Kernel extracted for lab T3 only — not a Ryoku product kernel claim."
