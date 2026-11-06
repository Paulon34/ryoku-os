#!/usr/bin/env bash
# Fetch + verify the Mission 005 reference Alpine virt ISO.
# DEFAULT: dry-run only (no download). Set RYOKU_FETCH_EXECUTE=1 to actually fetch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MANIFEST="$ROOT/tests/qemu/fixtures/reference-image.manifest"
RUN_DIR="$ROOT/tests/qemu/run"
EXECUTE="${RYOKU_FETCH_EXECUTE:-0}"

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
FILE="$(manifest_get filename)"
LOCAL_REL="$(manifest_get local_relpath)"
DEST="$ROOT/tests/qemu/$LOCAL_REL"

echo "Ryoku reference image fetch"
echo "  manifest: $MANIFEST"
echo "  url:      $URL"
echo "  sha256:   $SHA"
echo "  dest:     $DEST"
echo "  execute:  $EXECUTE (0=dry-run, 1=download+verify)"

if [[ "$EXECUTE" != "1" ]]; then
  echo
  echo "DRY-RUN: no bytes downloaded. To execute after authorization:"
  echo "  RYOKU_FETCH_EXECUTE=1 $0"
  echo
  echo "Example commands that WOULD run:"
  echo "  mkdir -p '$RUN_DIR'"
  echo "  curl -fL --retry 3 -o '$DEST' '$URL'"
  echo "  echo '$SHA  $DEST' | sha256sum -c -"
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
echo "Downloading…"
curl -fL --retry 3 -o "$DEST" "$URL"
echo "Verifying SHA-256…"
echo "$SHA  $DEST" | sha256sum -c -
echo "OK: $DEST"
echo "NOTE: This is Alpine reference Linux — NOT Ryoku OS."
