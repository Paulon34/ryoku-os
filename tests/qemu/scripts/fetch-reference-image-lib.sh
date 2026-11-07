#!/usr/bin/env bash
# Shared helpers for fetch-reference-image.sh (sourced by the main script and policy tests).
# Do not execute this file directly for ISO download.
#
# Security contract:
# - HTTPS only; host must match the per-URL allowlist pin
# - Redirects: never use curl -L. Each hop is inspected; Location host must match allowlist
#   before the next request. A hop through a forbidden host is rejected even if the final
#   destination would be allowlisted.
# - GPG: fail-closed — exit code must be 0 AND GOODSIG + VALIDSIG(fingerprint) required.

# shellcheck disable=SC2034  # exported for callers
: "${CURL_UA:=ryoku-virtlab-fetch/1}"
: "${MAX_REDIRS:=5}"

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
    return 1
  fi
  return 0
}

# Resolve a possibly-relative Location against the current request URL → absolute URL.
resolve_location() {
  local base_url="$1"
  local location="$2"
  python3 - "$base_url" "$location" <<'PY'
import sys
from urllib.parse import urljoin, urlparse
base, loc = sys.argv[1], sys.argv[2]
abs_url = urljoin(base, loc)
u = urlparse(abs_url)
if u.scheme != "https":
    raise SystemExit("refusing non-https redirect Location: " + abs_url)
if not u.hostname:
    raise SystemExit("redirect Location missing host: " + abs_url)
print(abs_url)
PY
}

# Download to dest without curl -L. Validate every redirect hop's host before following.
# Returns 0 on success. Writes the final URL to effective_file.
curl_authorized() {
  local url="$1"
  local dest="$2"
  local expect_host="$3"
  local effective_file="$4"
  local work="${5:-}"
  local current hops=0
  local hdr_file body_file http_code location

  local own_work=0
  if [[ -z "$work" ]]; then
    work="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-curl.XXXXXX")"
    own_work=1
  fi
  mkdir -p "$work"
  hdr_file="$work/headers.$BASHPID.$$"
  body_file="$work/body.$BASHPID.$$"

  current="$url"
  if ! require_https_host "$current" "$expect_host"; then
    if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
    return 1
  fi

  while true; do
    if (( hops > MAX_REDIRS )); then
      echo "error: exceeded max redirect hops ($MAX_REDIRS) starting from $url" >&2
      if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
      return 1
    fi

    if ! require_https_host "$current" "$expect_host"; then
      echo "error: redirect hop #$hops left allowlist (url=$current)" >&2
      if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
      return 1
    fi

    : >"$hdr_file"
    : >"$body_file"
    # Important: --max-redirs 0 and NO -L — we never silently follow.
    http_code="000"
    http_code="$(
      curl -sS --max-redirs 0 -A "$CURL_UA" \
        -D "$hdr_file" \
        -o "$body_file" \
        -w '%{http_code}' \
        "$current"
    )" || http_code="000"

    case "$http_code" in
      200)
        cp -f "$body_file" "$dest"
        printf '%s\n' "$current" >"$effective_file"
        echo "OK: downloaded $current (HTTP 200, hops=$hops) → $dest"
        if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
        return 0
        ;;
      301|302|303|307|308)
        location="$(
          awk 'BEGIN{IGNORECASE=1}
               /^Location:/{ sub(/\r$/,""); sub(/^Location:[[:space:]]*/,""); print; exit }
              ' "$hdr_file"
        )"
        if [[ -z "$location" ]]; then
          echo "error: HTTP $http_code without Location from $current" >&2
          if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
          return 1
        fi
        if ! current="$(resolve_location "$current" "$location")"; then
          if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
          return 1
        fi
        # Validate NEXT hop before fetching it (including when it later returns to allowlist).
        if ! require_https_host "$current" "$expect_host"; then
          echo "error: refusing redirect hop to unauthorized host before fetch: $current" >&2
          if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
          return 1
        fi
        hops=$((hops + 1))
        ;;
      *)
        echo "error: unexpected HTTP $http_code from $current (no silent redirect follow)" >&2
        if [[ "$own_work" -eq 1 ]]; then rm -rf "$work"; fi
        return 1
        ;;
    esac
  done
}

# Fail-closed detached signature verify.
# Requires: gpg exit 0 + GOODSIG + VALIDSIG matching expect_fpr.
gpg_verify_fail_closed() {
  local key_file="$1"
  local sig_file="$2"
  local data_file="$3"
  local expect_fpr="$4"
  local workdir="$5"
  local status_file gpg_err gpg_out gpg_rc imported_fpr

  export GNUPGHOME="$workdir/gnupg"
  mkdir -m 700 -p "$GNUPGHOME"
  status_file="$workdir/gpg.status"
  gpg_err="$workdir/gpg.stderr"
  gpg_out="$workdir/gpg.stdout"
  : >"$status_file"

  gpg --batch --import "$key_file" >"$workdir/gpg-import.out" 2>"$workdir/gpg-import.err"
  imported_fpr="$(gpg --batch --with-colons --fingerprint | awk -F: '/^fpr:/ {print $10; exit}')"
  if [[ "$imported_fpr" != "$expect_fpr" ]]; then
    echo "error: imported key fingerprint mismatch" >&2
    echo "  expected: $expect_fpr" >&2
    echo "  got:      $imported_fpr" >&2
    return 1
  fi
  echo "OK: key fingerprint $expect_fpr"

  # Do not toggle shell `set -e` here — it would leak to callers (e.g. test harness).
  gpg_rc=0
  gpg --batch --status-file "$status_file" --verify "$sig_file" "$data_file" \
    >"$gpg_out" 2>"$gpg_err" || gpg_rc=$?

  if [[ "$gpg_rc" -ne 0 ]]; then
    echo "error: GPG exit $gpg_rc — fail-closed (positive status markers alone are insufficient)" >&2
    if [[ -s "$status_file" ]]; then cat "$status_file" >&2; fi
    if [[ -s "$gpg_err" ]]; then cat "$gpg_err" >&2; fi
    return 1
  fi
  if [[ ! -s "$status_file" ]]; then
    echo "error: GPG produced no status file — aborting" >&2
    if [[ -s "$gpg_err" ]]; then cat "$gpg_err" >&2; fi
    return 1
  fi
  if ! grep -F '[GNUPG:] GOODSIG' "$status_file" >/dev/null; then
    echo "error: GPG GOODSIG missing — aborting" >&2
    cat "$status_file" >&2
    return 1
  fi
  if ! awk -v fpr="$expect_fpr" '
      $1 == "[GNUPG:]" && $2 == "VALIDSIG" && $3 == fpr { found=1 }
      END { exit found ? 0 : 1 }
    ' "$status_file"; then
    echo "error: VALIDSIG fingerprint did not match pin $expect_fpr" >&2
    cat "$status_file" >&2
    return 1
  fi
  if grep -E '\[GNUPG:\] (BADSIG|NO_PUBKEY|ERRSIG|EXPKEYSIG|REVKEYSIG)' "$status_file" >/dev/null; then
    echo "error: GPG reported a hard failure status despite exit 0" >&2
    cat "$status_file" >&2
    return 1
  fi
  echo "OK: GPG exit 0 + GOODSIG + VALIDSIG for $expect_fpr"
  return 0
}
