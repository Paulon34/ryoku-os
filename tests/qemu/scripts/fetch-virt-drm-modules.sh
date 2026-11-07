#!/usr/bin/env bash
# Fetch Alpine netboot modloop and extract allowlisted DRM modules (Mission 014.1).
# DEFAULT: dry-run. Set RYOKU_DRM_MODULES_EXECUTE=1 to download/extract/verify.
# Never uses NixOS/host /lib/modules. Never mixes 6.12.115 modules with 6.12.114 kernel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MANIFEST="$ROOT/tests/qemu/fixtures/virt-drm-modules.manifest"
OUT_DIR="$ROOT/tests/qemu/run/virt-drm-modules"
EXECUTE="${RYOKU_DRM_MODULES_EXECUTE:-0}"
ALLOWED_HOST="dl-cdn.alpinelinux.org"

manifest_get_first() {
  local key="$1"
  awk -F' = ' -v k="$key" '$1 == k { print $2; exit }' "$MANIFEST"
}

manifest_modules() {
  # Print module paths in order (paired with following module_sha256 lines).
  awk -F' = ' '
    $1 == "module" { path=$2 }
    $1 == "module_sha256" { print path " " $2 }
  ' "$MANIFEST"
}

MODLOOP_URL="$(manifest_get_first modloop_url)"
MODLOOP_SHA="$(manifest_get_first modloop_sha256)"
KERNEL_REL="$(manifest_get_first kernel_release)"
PREFIX="$(manifest_get_first modloop_member_prefix)"
GUEST_ROOT="$(manifest_get_first guest_modules_root)"

echo "Ryoku virt DRM modules fetch (Mission 014.1)"
echo "  manifest: $MANIFEST"
echo "  kernel:   $KERNEL_REL"
echo "  out:      $OUT_DIR"
echo "  execute:  $EXECUTE (0=dry-run)"

if [[ "$EXECUTE" != "1" ]]; then
  echo "DRY-RUN: would download pinned modloop, unsquash allowlisted .ko, verify SHA-256"
  echo "  RYOKU_DRM_MODULES_EXECUTE=1 $0"
  exit 0
fi

case "$MODLOOP_URL" in
  https://dl-cdn.alpinelinux.org/*) ;;
  *) echo "error: modloop URL host not allowlisted"; exit 1 ;;
esac

command -v unsquashfs >/dev/null || { echo "error: unsquashfs required (squashfs-tools)"; exit 1; }
command -v sha256sum >/dev/null || { echo "error: sha256sum required"; exit 1; }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-drm-mod.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "Downloading modloop…"
curl -fsSL --proto '=https' --tlsv1.2 -o "$WORKDIR/modloop-virt" "$MODLOOP_URL"
got="$(sha256sum "$WORKDIR/modloop-virt" | awk '{print $1}')"
if [[ "$got" != "$MODLOOP_SHA" ]]; then
  echo "error: modloop sha256 mismatch (got $got expected $MODLOOP_SHA)" >&2
  exit 1
fi
echo "OK: modloop sha256 matches pin"

echo "Extracting squashfs…"
unsquashfs -d "$WORKDIR/sq" "$WORKDIR/modloop-virt" >/dev/null

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
SUMS="$OUT_DIR/SHA256SUMS.txt"
: >"$SUMS"

while read -r rel expect; do
  [[ -n "$rel" ]] || continue
  src="$WORKDIR/sq/${PREFIX}${rel}"
  if [[ ! -f "$src" ]]; then
    echo "error: missing module in modloop: $PREFIX$rel" >&2
    exit 1
  fi
  got="$(sha256sum "$src" | awk '{print $1}')"
  if [[ "$got" != "$expect" ]]; then
    echo "error: module sha256 mismatch for $rel (got $got expected $expect)" >&2
    exit 1
  fi
  # vermagic gate (grep -a: avoid pipefail+SIGPIPE flake from `strings | grep -q`)
  if ! grep -a -F -q "vermagic=${KERNEL_REL}" "$src"; then
    echo "error: vermagic does not contain ${KERNEL_REL} in $rel" >&2
    exit 1
  fi
  dest_dir="$OUT_DIR/$(dirname "$rel")"
  mkdir -p "$dest_dir"
  cp -a "$src" "$dest_dir/"
  echo "$got  $GUEST_ROOT/$rel" >>"$SUMS"
  echo "OK: $rel"
done < <(manifest_modules)

# Record provenance
{
  echo "# Provenance"
  echo "modloop_url=$MODLOOP_URL"
  echo "modloop_sha256=$MODLOOP_SHA"
  echo "kernel_release=$KERNEL_REL"
  echo "guest_modules_root=$GUEST_ROOT"
} >"$OUT_DIR/PROVENANCE.txt"

echo "OK: modules staged under $OUT_DIR"
echo "NOTE: FIRST_PIXELS still NOT_RUN until guest visual confirmation."
