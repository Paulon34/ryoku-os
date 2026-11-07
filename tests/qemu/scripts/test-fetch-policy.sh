#!/usr/bin/env bash
# Mock policy tests for fetch-reference-image-lib.sh
# Does NOT download the Alpine ISO. Safe to run on the Cursor host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=fetch-reference-image-lib.sh
source "$SCRIPT_DIR/fetch-reference-image-lib.sh"

PASS=0
FAIL=0
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-fetch-policy.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

assert_fail() {
  local name="$1"
  shift
  set +e
  "$@" >"$WORKDIR/out.$name" 2>"$WORKDIR/err.$name"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "PASS: $name (rejected as expected, rc=$rc)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (expected rejection, got success)" >&2
    cat "$WORKDIR/err.$name" >&2 || true
    FAIL=$((FAIL + 1))
  fi
}

assert_ok() {
  local name="$1"
  shift
  set +e
  "$@" >"$WORKDIR/out.$name" 2>"$WORKDIR/err.$name"
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (expected success, rc=$rc)" >&2
    cat "$WORKDIR/err.$name" >&2 || true
    FAIL=$((FAIL + 1))
  fi
}

# --- Test 1: GPG positive status + non-zero exit must be rejected (fail-closed) ---
install_mock_gpg_nonzero() {
  local bindir="$1"
  local fpr="$2"
  mkdir -p "$bindir"
  cat >"$bindir/gpg" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# Minimal mock: honor --status-file and --fingerprint; always exit 1 on --verify
status_file=""
args=("\$@")
i=0
while [[ \$i -lt \${#args[@]} ]]; do
  if [[ "\${args[\$i]}" == "--status-file" ]]; then
    i=\$((i+1))
    status_file="\${args[\$i]}"
  fi
  i=\$((i+1))
done
if [[ "\$*" == *"--fingerprint"* ]]; then
  echo "fpr:::::::::${fpr}:"
  exit 0
fi
if [[ "\$*" == *"--import"* ]]; then
  exit 0
fi
if [[ "\$*" == *"--verify"* ]]; then
  if [[ -n "\$status_file" ]]; then
    {
      echo "[GNUPG:] NEWSIG"
      echo "[GNUPG:] GOODSIG AABBCCDDEEFF0011 Natanael Copa <ncopa@alpinelinux.org>"
      echo "[GNUPG:] VALIDSIG ${fpr} 2026-10-21 ..."
    } >"\$status_file"
  fi
  echo "mock gpg: writing GOODSIG/VALIDSIG but exiting 1" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$bindir/gpg"
}

echo "== GPG fail-closed =="
FPR_FAKE="0482D84022F52DF1C4E7CD43293ACD0907D9495A"
MOCK_BIN="$WORKDIR/mock-gpg-bin"
install_mock_gpg_nonzero "$MOCK_BIN" "$FPR_FAKE"
export PATH="$MOCK_BIN:$PATH"
# Dummy key/sig/data files (mock gpg ignores contents on verify)
: >"$WORKDIR/dummy.key"
: >"$WORKDIR/dummy.sig"
echo payload >"$WORKDIR/dummy.data"
assert_fail "gpg_positive_status_nonzero_exit_rejected" \
  gpg_verify_fail_closed "$WORKDIR/dummy.key" "$WORKDIR/dummy.sig" "$WORKDIR/dummy.data" "$FPR_FAKE" "$WORKDIR/gpg-work"

# --- Test 2: redirect through forbidden host must reject (even if final is allowlisted) ---
install_mock_curl_evil_hop() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat >"$bindir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Parse -D headers -o body -w '%{http_code}' URL (last arg)
out_body="/dev/null"
hdr="/dev/null"
url=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    -D) i=$((i+1)); hdr="${args[$i]}" ;;
    -o) i=$((i+1)); out_body="${args[$i]}" ;;
    -w) i=$((i+1)) ;; # ignore format; we print code ourselves
    -A|--max-redirs|-sS) ;;
    https://*|http://*) url="${args[$i]}" ;;
  esac
  i=$((i+1))
done

case "$url" in
  https://dl-cdn.alpinelinux.org/start)
    printf 'HTTP/1.1 302 Found\r\nLocation: https://evil.example/steal\r\n\r\n' >"$hdr"
    : >"$out_body"
    printf '302'
    ;;
  https://evil.example/steal)
    # Would return to allowlist — must never be fetched if hop check works.
    printf 'HTTP/1.1 302 Found\r\nLocation: https://dl-cdn.alpinelinux.org/final\r\n\r\n' >"$hdr"
    : >"$out_body"
    printf '302'
    ;;
  https://dl-cdn.alpinelinux.org/final)
    printf 'HTTP/1.1 200 OK\r\n\r\n' >"$hdr"
    echo 'ISOBYTES' >"$out_body"
    printf '200'
    ;;
  *)
    echo "mock curl: unexpected url $url" >&2
    printf '500'
    exit 1
    ;;
esac
EOF
  chmod +x "$bindir/curl"
}

echo "== Redirect hop allowlist =="
MOCK_CURL_BIN="$WORKDIR/mock-curl-bin"
install_mock_curl_evil_hop "$MOCK_CURL_BIN"
# Prefer mock curl over system curl for this test only.
export PATH="$MOCK_CURL_BIN:$MOCK_BIN:$PATH"

assert_fail "redirect_via_forbidden_host_even_if_final_allowed" \
  curl_authorized \
    "https://dl-cdn.alpinelinux.org/start" \
    "$WORKDIR/out.bin" \
    "dl-cdn.alpinelinux.org" \
    "$WORKDIR/effective.url" \
    "$WORKDIR/curl-work"

# Ensure we never wrote the final payload (forbidden hop aborted first).
if [[ -f "$WORKDIR/out.bin" ]] && grep -q ISOBYTES "$WORKDIR/out.bin" 2>/dev/null; then
  echo "FAIL: payload from post-evil hop was written" >&2
  FAIL=$((FAIL + 1))
else
  echo "PASS: no content fetched from/through forbidden hop"
  PASS=$((PASS + 1))
fi

# --- Test 3: same-host redirect then 200 should succeed ---
install_mock_curl_same_host() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat >"$bindir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out_body="/dev/null"
hdr="/dev/null"
url=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    -D) i=$((i+1)); hdr="${args[$i]}" ;;
    -o) i=$((i+1)); out_body="${args[$i]}" ;;
    -w) i=$((i+1)) ;;
    -A|--max-redirs|-sS) ;;
    https://*|http://*) url="${args[$i]}" ;;
  esac
  i=$((i+1))
done
case "$url" in
  https://dl-cdn.alpinelinux.org/a)
    printf 'HTTP/1.1 302 Found\r\nLocation: https://dl-cdn.alpinelinux.org/b\r\n\r\n' >"$hdr"
    : >"$out_body"
    printf '302'
    ;;
  https://dl-cdn.alpinelinux.org/b)
    printf 'HTTP/1.1 200 OK\r\n\r\n' >"$hdr"
    echo 'OKBODY' >"$out_body"
    printf '200'
    ;;
  *)
    echo "mock curl unexpected $url" >&2
    printf '500'
    exit 1
    ;;
esac
EOF
  chmod +x "$bindir/curl"
}

echo "== Same-host redirect OK =="
install_mock_curl_same_host "$MOCK_CURL_BIN"
assert_ok "same_host_redirect_then_200" \
  curl_authorized \
    "https://dl-cdn.alpinelinux.org/a" \
    "$WORKDIR/ok.bin" \
    "dl-cdn.alpinelinux.org" \
    "$WORKDIR/ok.effective" \
    "$WORKDIR/curl-ok"
if [[ -f "$WORKDIR/ok.bin" ]] && grep -q OKBODY "$WORKDIR/ok.bin"; then
  echo "PASS: same-host redirect delivered body"
  PASS=$((PASS + 1))
else
  echo "FAIL: same-host redirect body missing" >&2
  FAIL=$((FAIL + 1))
fi

echo
echo "Summary: $PASS passed, $FAIL failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
