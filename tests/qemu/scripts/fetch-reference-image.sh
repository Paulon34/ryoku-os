#!/usr/bin/env bash
# Fetch + verify the Mission 005/006 reference Alpine virt ISO.
# DEFAULT: dry-run only (no download). Set RYOKU_FETCH_EXECUTE=1 to actually fetch.
#
# Authorized download hosts only (disposable runners / reviewed hosts — never commit ISO).
# Verification order:
#   1) URL host allowlist (HTTPS only)
#   2) Download with redirect following, then re-check *effective* URL host
#   3) Official .sha256 lists the pinned digest
#   4) ISO bytes match pinned SHA-256 (abort on mismatch)
#   5) Detached .asc verified with Alpine ncopa key + pinned fingerprint
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MANIFEST="$ROOT/tests/qemu/fixtures/reference-image.manifest"
RUN_DIR="$ROOT/tests/qemu/run"
EXECUTE="${RYOKU_FETCH_EXECUTE:-0}"
VERIFY_GPG="${RYOKU_VERIFY_GPG:-1}"
ALLOWED_HOST="dl-cdn.alpinelinux.org"
ALLOWED_KEY_HOST="alpinelinux.org"
CURL_UA="ryoku-virtlab-fetch/1"
MAX_REDIRS=5

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

https_host() {
  local url="$1"
  python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
if u.scheme != "https":
    raise SystemExit("refusing non-https URL: " + sys.argv[1])
print(u.hostname or "")
PY
}

require_https_host() {
  local url="$1"
  local expect_host="$2"
  local host
  host="$(https_host "$url")"
  if [[ "$host" != "$expect_host" ]]; then
    echo "error: refusing host '$host' (allowed: $expect_host) for $url" >&2
    exit 1
  fi
}

# Download to dest; follow redirects but abort if the *effective* URL leaves expect_host.
# Single curl invocation — body to dest, metadata on stdout (no second ISO download).
curl_authorized() {
  local url="$1"
  local dest="$2"
  local expect_host="$3"
  local effective_file="$4"
  local meta http_code effective

  require_https_host "$url" "$expect_host"

  meta="$(
    curl -fL --max-redirs "$MAX_REDIRS" -A "$CURL_UA" \
      -o "$dest" \
      -w '%{http_code}\t%{url_effective}' \
      "$url"
  )"
  http_code="${meta%%$'\t'*}"
  effective="${meta#*$'\t'}"
  printf '%s\n' "$effective" >"$effective_file"
  require_https_host "$effective" "$expect_host"
  if [[ "$http_code" != "200" ]]; then
    echo "error: unexpected HTTP status $http_code for $url (effective=$effective)" >&2
    exit 1
  fi
  echo "OK: downloaded via $effective (HTTP $http_code) → $dest"
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
  echo "Example commands that WOULD run (with redirect host re-check + GPG status-file):"
  echo "  mkdir -p '$RUN_DIR'"
  echo "  # curl -fL --max-redirs $MAX_REDIRS … then require effective host == allowlist"
  echo "  # sha256 pin + official .sha256 cross-check"
  echo "  # gpg --status-file … --verify (GOODSIG + VALIDSIG \$FPR)"
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
curl_authorized "$SHA_URL" "$SHA_DEST" "$ALLOWED_HOST" "$WORKDIR/sha.effective"
if ! grep -qiE "^${SHA}[[:space:]]+${FILE}\$" "$SHA_DEST"; then
  echo "error: official sha256 file does not list pinned digest for $FILE" >&2
  echo "--- $SHA_DEST ---" >&2
  cat "$SHA_DEST" >&2
  exit 1
fi
echo "OK: official sha256 listing matches pin"

echo "Downloading ISO…"
curl_authorized "$URL" "$DEST" "$ALLOWED_HOST" "$WORKDIR/iso.effective"
echo "Verifying ISO SHA-256 against pin…"
echo "$SHA  $DEST" | sha256sum -c -
echo "OK: ISO digest matches pin $SHA"

if [[ "$VERIFY_GPG" == "1" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "error: gpg not found but RYOKU_VERIFY_GPG=1 (install gnupg or set RYOKU_VERIFY_GPG=0 only if reviewed)" >&2
    exit 1
  fi
  echo "Downloading detached signature + Alpine release key…"
  curl_authorized "$SIG_URL" "$SIG_DEST" "$ALLOWED_HOST" "$WORKDIR/sig.effective"
  curl_authorized "$KEY_URL" "$KEY_DEST" "$ALLOWED_KEY_HOST" "$WORKDIR/key.effective"

  export GNUPGHOME="$WORKDIR/gnupg"
  mkdir -m 700 "$GNUPGHOME"
  STATUS_FILE="$WORKDIR/gpg.status"
  GPG_ERR="$WORKDIR/gpg.stderr"
  GPG_OUT="$WORKDIR/gpg.stdout"

  gpg --batch --import "$KEY_DEST" >"$WORKDIR/gpg-import.out" 2>"$WORKDIR/gpg-import.err"
  imported_fpr="$(gpg --batch --with-colons --fingerprint | awk -F: '/^fpr:/ {print $10; exit}')"
  if [[ "$imported_fpr" != "$FPR" ]]; then
    echo "error: imported key fingerprint mismatch" >&2
    echo "  expected: $FPR" >&2
    echo "  got:      $imported_fpr" >&2
    exit 1
  fi
  echo "OK: Alpine key fingerprint $FPR"

  echo "Verifying detached GPG signature…"
  # Avoid fragile tee|grep -q under pipefail: write status to a private file, then inspect.
  set +e
  gpg --batch --status-file "$STATUS_FILE" --verify "$SIG_DEST" "$DEST" \
    >"$GPG_OUT" 2>"$GPG_ERR"
  gpg_rc=$?
  set -e

  if [[ ! -s "$STATUS_FILE" ]]; then
    echo "error: GPG produced no status file — aborting" >&2
    cat "$GPG_ERR" >&2 || true
    exit 1
  fi
  if ! grep -F '[GNUPG:] GOODSIG' "$STATUS_FILE" >/dev/null; then
    echo "error: GPG GOODSIG missing — aborting (rc=$gpg_rc)" >&2
    cat "$STATUS_FILE" >&2
    cat "$GPG_ERR" >&2 || true
    exit 1
  fi
  # VALIDSIG <fingerprint> … — fingerprint must match the pin exactly.
  if ! awk -v fpr="$FPR" '
      $1 == "[GNUPG:]" && $2 == "VALIDSIG" && $3 == fpr { found=1 }
      END { exit found ? 0 : 1 }
    ' "$STATUS_FILE"; then
    echo "error: VALIDSIG fingerprint did not match pin $FPR" >&2
    cat "$STATUS_FILE" >&2
    exit 1
  fi
  # Prefer a clean verify exit code, but still accept 0/… if status lines prove GOODSIG+VALIDSIG
  # (gpg may warn about untrusted ultimate trust without failing authenticity).
  if [[ "$gpg_rc" -ne 0 ]]; then
    # With GOODSIG+VALIDSIG present, non-zero is typically "not trusted" warning path on some builds.
    # Abort only if BADSIG / NO_PUBKEY / ERRSIG appear.
    if grep -E '\[GNUPG:\] (BADSIG|NO_PUBKEY|ERRSIG|EXPKEYSIG|REVKEYSIG)' "$STATUS_FILE" >/dev/null; then
      echo "error: GPG reported a hard failure status (rc=$gpg_rc)" >&2
      cat "$STATUS_FILE" >&2
      exit 1
    fi
    echo "WARN: gpg exit $gpg_rc with GOODSIG+VALIDSIG (likely trust-model warning); accepting authenticity"
  fi
  echo "OK: GPG GOODSIG / VALIDSIG for $FPR"
else
  echo "WARN: RYOKU_VERIFY_GPG=0 — signature step skipped (SHA-256 still enforced)"
fi

echo "OK: $DEST"
echo "NOTE: This is Alpine reference Linux — NOT Ryoku OS."
# WORKDIR cleaned by trap
