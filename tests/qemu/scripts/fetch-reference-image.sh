#!/usr/bin/env bash
# Fetch + verify the Mission 005/006 reference Alpine virt ISO.
# DEFAULT: dry-run only (no download). Set RYOKU_FETCH_EXECUTE=1 to actually fetch.
#
# Authorized download hosts only (disposable runners / reviewed hosts — never commit ISO).
# Verification order:
#   1) URL host allowlist (HTTPS only)
#   2) Hop-by-hop download (no curl -L); every redirect Location must stay on allowlist
#   3) Official .sha256 lists the pinned digest
#   4) ISO bytes match pinned SHA-256 (abort on mismatch)
#   5) Detached .asc: fail-closed GPG (exit 0 + GOODSIG + VALIDSIG fingerprint)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=fetch-reference-image-lib.sh
source "$SCRIPT_DIR/fetch-reference-image-lib.sh"

MANIFEST="$ROOT/tests/qemu/fixtures/reference-image.manifest"
RUN_DIR="$ROOT/tests/qemu/run"
EXECUTE="${RYOKU_FETCH_EXECUTE:-0}"
VERIFY_GPG="${RYOKU_VERIFY_GPG:-1}"
ALLOWED_HOST="dl-cdn.alpinelinux.org"
ALLOWED_KEY_HOST="alpinelinux.org"

manifest_get() {
  local key="$1"
  awk -F'=' -v k="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ /^[[:space:]]*$/ { next }
    {
      key=$1; sub(/^[[:space:]]+/, "", key); sub(/[[:space:]]+$/, "", key)
      val=substr($0, index($0,"=")+1); sub(/^[[:space:]]+/, "", val); sub(/[[:space:]]+$/, "", val)
      if (key==k) { print val; exit }
    }
  ' "$MANIFEST"
}

URL="$(manifest_get url)"
SHA="$(manifest_get sha256)"
SHA_URL="$(manifest_get sha256_url)"
SIG_URL="$(manifest_get signature_url)"
KEY_URL="$(manifest_get gpg_key_url)"
FPR="$(manifest_get gpg_fingerprint)"
FILE="$(manifest_get filename)"
LOCAL_REL="$(manifest_get local_relpath)"
DEST="$ROOT/tests/qemu/$LOCAL_REL"
SHA_DEST="$RUN_DIR/${FILE}.sha256"
SIG_DEST="$RUN_DIR/${FILE}.asc"
KEY_DEST="$RUN_DIR/ncopa.asc"

echo "Ryoku reference image fetch"
echo "  manifest: $MANIFEST"
echo "  url:      $URL"
echo "  sha256:   $SHA"
echo "  sha_url:  $SHA_URL"
echo "  sig_url:  $SIG_URL"
echo "  key_url:  $KEY_URL"
echo "  fpr:      $FPR"
echo "  dest:     $DEST"
echo "  execute:  $EXECUTE (0=dry-run, 1=download+verify)"
echo "  gpg:      $VERIFY_GPG (1=verify detached signature when possible)"
echo "  redirects: hop-by-hop allowlist (no curl -L)"

require_https_host "$URL" "$ALLOWED_HOST"
require_https_host "$SHA_URL" "$ALLOWED_HOST"
require_https_host "$SIG_URL" "$ALLOWED_HOST"
require_https_host "$KEY_URL" "$ALLOWED_KEY_HOST"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: no bytes downloaded. To execute after authorization on a disposable runner:"
  echo "  RYOKU_FETCH_EXECUTE=1 $0"
  echo
  echo "Policy: hop-by-hop HTTPS allowlist; GPG fail-closed (exit 0 + GOODSIG + VALIDSIG)."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl not found" >&2
  exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "error: sha256sum not found" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-fetch.XXXXXX")"
cleanup_work() { rm -rf "$WORKDIR"; }
trap cleanup_work EXIT

mkdir -p "$RUN_DIR"

echo "Downloading official SHA-256 listing…"
curl_authorized "$SHA_URL" "$SHA_DEST" "$ALLOWED_HOST" "$WORKDIR/sha.effective" "$WORKDIR/curl-sha"
if ! grep -qiE "^${SHA}[[:space:]]+${FILE}\$" "$SHA_DEST"; then
  echo "error: official sha256 file does not list pinned digest for $FILE" >&2
  echo "--- $SHA_DEST ---" >&2
  cat "$SHA_DEST" >&2
  exit 1
fi
echo "OK: official sha256 listing matches pin"

echo "Downloading ISO…"
curl_authorized "$URL" "$DEST" "$ALLOWED_HOST" "$WORKDIR/iso.effective" "$WORKDIR/curl-iso"
echo "Verifying ISO SHA-256 against pin…"
echo "$SHA  $DEST" | sha256sum -c -
echo "OK: ISO digest matches pin $SHA"

if [[ "$VERIFY_GPG" == "1" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "error: gpg not found but RYOKU_VERIFY_GPG=1 (install gnupg or set RYOKU_VERIFY_GPG=0 only if reviewed)" >&2
    exit 1
  fi
  echo "Downloading detached signature + Alpine release key…"
  curl_authorized "$SIG_URL" "$SIG_DEST" "$ALLOWED_HOST" "$WORKDIR/sig.effective" "$WORKDIR/curl-sig"
  curl_authorized "$KEY_URL" "$KEY_DEST" "$ALLOWED_KEY_HOST" "$WORKDIR/key.effective" "$WORKDIR/curl-key"

  gpg_verify_fail_closed "$KEY_DEST" "$SIG_DEST" "$DEST" "$FPR" "$WORKDIR"
else
  echo "WARN: RYOKU_VERIFY_GPG=0 — signature step skipped (SHA-256 still enforced)"
fi

echo "OK: $DEST"
echo "NOTE: This is Alpine reference Linux — NOT Ryoku OS."
