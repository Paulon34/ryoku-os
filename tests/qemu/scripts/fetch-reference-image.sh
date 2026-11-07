#!/usr/bin/env bash
# Fetch + verify the Mission 005/006 reference Alpine virt ISO.
# DEFAULT: dry-run only (no download). Set RYOKU_FETCH_EXECUTE=1 to actually fetch.
#
# Authorized download hosts only (disposable runners / reviewed hosts — never commit ISO).
# Verification order:
#   1) URL host allowlist
#   2) Official .sha256 lists the pinned digest
#   3) ISO bytes match pinned SHA-256 (abort on mismatch)
#   4) Detached .asc verified with Alpine ncopa key when trust chain available
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
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

require_https_host() {
  local url="$1"
  local expect_host="$2"
  local host
  host="$(python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
if u.scheme != "https":
    raise SystemExit("refusing non-https URL")
print(u.hostname or "")
PY
)"
  if [[ "$host" != "$expect_host" ]]; then
    echo "error: refusing host '$host' (allowed: $expect_host) for $url" >&2
    exit 1
  fi
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

require_https_host "$URL" "$ALLOWED_HOST"
require_https_host "$SHA_URL" "$ALLOWED_HOST"
require_https_host "$SIG_URL" "$ALLOWED_HOST"
require_https_host "$KEY_URL" "$ALLOWED_KEY_HOST"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: no bytes downloaded. To execute after authorization on a disposable runner:"
  echo "  RYOKU_FETCH_EXECUTE=1 $0"
  echo
  echo "Example commands that WOULD run:"
  echo "  mkdir -p '$RUN_DIR'"
  echo "  curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o '$DEST' '$URL'"
  echo "  curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o '$SHA_DEST' '$SHA_URL'"
  echo "  curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o '$SIG_DEST' '$SIG_URL'"
  echo "  curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o '$KEY_DEST' '$KEY_URL'"
  echo "  # cross-check official sha256 file contains pinned digest"
  echo "  echo '$SHA  $DEST' | sha256sum -c -"
  echo "  gpg --import '$KEY_DEST' && gpg --verify '$SIG_DEST' '$DEST'"
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

mkdir -p "$RUN_DIR"

echo "Downloading official SHA-256 listing…"
curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o "$SHA_DEST" "$SHA_URL"
if ! grep -qiE "^${SHA}[[:space:]]+${FILE}\$" "$SHA_DEST"; then
  echo "error: official sha256 file does not list pinned digest for $FILE" >&2
  echo "--- $SHA_DEST ---" >&2
  cat "$SHA_DEST" >&2
  exit 1
fi
echo "OK: official sha256 listing matches pin"

echo "Downloading ISO…"
curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o "$DEST" "$URL"
echo "Verifying ISO SHA-256 against pin…"
echo "$SHA  $DEST" | sha256sum -c -
echo "OK: ISO digest matches pin $SHA"

if [[ "$VERIFY_GPG" == "1" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "error: gpg not found but RYOKU_VERIFY_GPG=1 (install gnupg or set RYOKU_VERIFY_GPG=0 only if reviewed)" >&2
    exit 1
  fi
  echo "Downloading detached signature + Alpine release key…"
  curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o "$SIG_DEST" "$SIG_URL"
  curl -fL --retry 3 -A 'ryoku-virtlab-fetch/1' -o "$KEY_DEST" "$KEY_URL"

  GNUPGHOME="$(mktemp -d)"
  export GNUPGHOME
  cleanup_gpg() { rm -rf "$GNUPGHOME"; }
  trap cleanup_gpg EXIT

  gpg --batch --import "$KEY_DEST" >/dev/null 2>&1
  imported_fpr="$(gpg --batch --with-colons --fingerprint | awk -F: '/^fpr:/ {print $10; exit}')"
  if [[ "$imported_fpr" != "$FPR" ]]; then
    echo "error: imported key fingerprint mismatch" >&2
    echo "  expected: $FPR" >&2
    echo "  got:      $imported_fpr" >&2
    exit 1
  fi
  echo "OK: Alpine key fingerprint $FPR"

  echo "Verifying detached GPG signature…"
  if ! gpg --batch --status-fd 1 --verify "$SIG_DEST" "$DEST" 2>/tmp/ryoku-gpg-verify.err | tee /tmp/ryoku-gpg-verify.out | grep -q '\[GNUPG:\] GOODSIG'; then
    echo "error: GPG signature verification failed — aborting" >&2
    cat /tmp/ryoku-gpg-verify.err >&2 || true
    cat /tmp/ryoku-gpg-verify.out >&2 || true
    exit 1
  fi
  if ! grep -q "\[GNUPG:\] VALIDSIG $FPR" /tmp/ryoku-gpg-verify.out; then
    echo "error: VALIDSIG fingerprint did not match pin $FPR" >&2
    cat /tmp/ryoku-gpg-verify.out >&2
    exit 1
  fi
  echo "OK: GPG GOODSIG / VALIDSIG for $FPR"
  trap - EXIT
  cleanup_gpg
else
  echo "WARN: RYOKU_VERIFY_GPG=0 — signature step skipped (SHA-256 still enforced)"
fi

echo "OK: $DEST"
echo "NOTE: This is Alpine reference Linux — NOT Ryoku OS."
