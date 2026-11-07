#!/usr/bin/env bash
# Policy tests for fetch-virt-drm-modules.sh (dry-run only — no download).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FETCH="$SCRIPT_DIR/fetch-virt-drm-modules.sh"
MANIFEST="$ROOT/tests/qemu/fixtures/virt-drm-modules.manifest"

PASS=0
FAIL=0

assert_ok() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_ok "manifest exists" test -f "$MANIFEST"
assert_ok "fetch script executable or chmod" bash -c "chmod +x '$FETCH'"
assert_ok "dry-run exits 0" env RYOKU_DRM_MODULES_EXECUTE=0 "$FETCH"
assert_ok "dry-run mentions DRY-RUN" bash -c "RYOKU_DRM_MODULES_EXECUTE=0 '$FETCH' | grep -q DRY-RUN"
assert_ok "manifest pins 6.12.114-0-virt" grep -q 'kernel_release = 6.12.114-0-virt' "$MANIFEST"
assert_ok "manifest pins netboot-3.21.9 modloop" grep -q 'netboot-3.21.9/modloop-virt' "$MANIFEST"
assert_ok "manifest lists virtio-gpu.ko" grep -q 'virtio-gpu.ko' "$MANIFEST"
assert_ok "manifest has fourteen module_sha256 lines (12 DRM + 2 input)" bash -c "test \$(grep -c '^module_sha256 = ' '$MANIFEST') -eq 14"

echo "virt-drm-modules policy: PASS=$PASS FAIL=$FAIL"
test "$FAIL" -eq 0
