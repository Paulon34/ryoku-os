#!/usr/bin/env bash
# Policy mocks for Mission 009 / 009.5 Boot Seed prep (no ISO download, no T3).
#
# Extract negatives run against a *copied* extractor whose ROOT resolves under
# mktemp — create/overwrite/rm of ISO/kernel fixtures never touch the real repo lab.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-prep-policy.XXXXXX")"
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

# Mini lab tree: extractor copy so dirname/.../../.. → TMPROOT (not the real repo).
TEMP_LAB="$TMPROOT/tests/qemu"
TEMP_RUN="$TEMP_LAB/run"
TEMP_SCRIPTS="$TEMP_LAB/scripts"
mkdir -p "$TEMP_RUN" "$TEMP_LAB/results" "$TEMP_SCRIPTS"
cp "$REPO_ROOT/tests/qemu/scripts/extract-boot-seed-kernel.sh" "$TEMP_SCRIPTS/extract-boot-seed-kernel.sh"
chmod +x "$TEMP_SCRIPTS/extract-boot-seed-kernel.sh"
EXTRACT="$TEMP_SCRIPTS/extract-boot-seed-kernel.sh"

# Snapshot real lab ISO/kernel presence — must be unchanged after extract negatives.
REAL_RUN="$REPO_ROOT/tests/qemu/run"
REAL_ISO="$REAL_RUN/alpine-virt-3.21.9-x86_64.iso"
REAL_VMLINUZ="$REAL_RUN/ryoku-boot-seed-vmlinuz"
real_iso_before=0
real_vmlinuz_before=0
[[ -e "$REAL_ISO" || -L "$REAL_ISO" ]] && real_iso_before=1
[[ -e "$REAL_VMLINUZ" || -L "$REAL_VMLINUZ" ]] && real_vmlinuz_before=1
real_iso_sha_before=""
real_vmlinuz_sha_before=""
[[ -f "$REAL_ISO" && ! -L "$REAL_ISO" ]] && real_iso_sha_before="$(sha256sum "$REAL_ISO" | awk '{print $1}')"
[[ -f "$REAL_VMLINUZ" && ! -L "$REAL_VMLINUZ" ]] && real_vmlinuz_sha_before="$(sha256sum "$REAL_VMLINUZ" | awk '{print $1}')"

echo "== extract-boot-seed-kernel dry-run (no download; temp ROOT) =="
dry_out="$(RYOKU_KERNEL_EXTRACT_EXECUTE=0 "$EXTRACT" 2>&1)"
if echo "$dry_out" | grep -q 'DRY-RUN' \
  && echo "$dry_out" | grep -F -q "$TEMP_RUN" \
  && ! echo "$dry_out" | grep -Eqi 'curl |wget |https://'; then
  pass "kernel_extract_dry_run_no_download"
else
  fail "kernel_extract_dry_run_no_download"
fi

echo "== prep-boot-seed-artifacts dry-run =="
if RYOKU_BOOT_SEED_PREP_EXECUTE=0 "$REPO_ROOT/tests/qemu/scripts/prep-boot-seed-artifacts.sh" \
  | grep -q 'DRY-RUN'; then
  pass "artifact_prep_dry_run"
else
  fail "artifact_prep_dry_run"
fi

echo "== initramfs builder dry-run =="
if RYOKU_INITRAMFS_EXECUTE=0 "$REPO_ROOT/tests/qemu/scripts/build-boot-seed-initramfs.sh" \
  | grep -q 'DRY-RUN'; then
  pass "initramfs_dry_run"
else
  fail "initramfs_dry_run"
fi

echo "== ALLOW_DYNAMIC blocked =="
allow_out="$TMPROOT/allow-dyn.out"
allow_err="$TMPROOT/allow-dyn.err"
if ! RYOKU_INITRAMFS_ALLOW_DYNAMIC=1 "$REPO_ROOT/tests/qemu/scripts/build-boot-seed-initramfs.sh" \
  >"$allow_out" 2>"$allow_err"; then
  if grep -qi 'blocked\|ALLOW_DYNAMIC' "$allow_err" "$allow_out"; then
    pass "allow_dynamic_blocked"
  else
    fail "allow_dynamic_blocked (exit nonzero but message missing)"
  fi
else
  fail "allow_dynamic_blocked (should exit nonzero)"
fi

echo "== workflow_dispatch + main-ref gate present =="
WF="$REPO_ROOT/.github/workflows/boot-seed-t3.yml"
if [[ -f "$WF" ]] \
  && grep -q 'workflow_dispatch' "$WF" \
  && grep -q "confirm == 'RUN'" "$WF" \
  && grep -q "github.ref == 'refs/heads/main'" "$WF" \
  && grep -q 'RYOKU_T3_EXECUTE' "$WF" \
  && grep -qE 'ref:\s*main' "$WF" \
  && ! grep -qE '^\s+push:' "$WF" \
  && ! grep -qE '^\s+pull_request:' "$WF"; then
  pass "workflow_manual_gate"
else
  fail "workflow_manual_gate"
fi

echo "== mock: main-ref condition required for job =="
# Negative: a dispatch-only if without main-ref must not satisfy the policy check.
MOCK_WF="$TMPROOT/boot-seed-t3-no-main-ref.yml"
cat >"$MOCK_WF" <<'EOF'
on:
  workflow_dispatch:
    inputs:
      confirm:
        type: string
jobs:
  boot-seed-t3:
    if: github.event.inputs.confirm == 'RUN'
    env:
      RYOKU_T3_EXECUTE: "1"
EOF
if grep -q "confirm == 'RUN'" "$MOCK_WF" \
  && ! grep -q "github.ref == 'refs/heads/main'" "$MOCK_WF" \
  && grep -q "github.ref == 'refs/heads/main'" "$WF"; then
  pass "workflow_main_ref_gate_mocked"
else
  fail "workflow_main_ref_gate_mocked"
fi

echo "== no kernel blob in git =="
if git -C "$REPO_ROOT" ls-files 'tests/qemu/run/*' 2>/dev/null | grep -E 'vmlinuz|cpio|\.iso$' >/dev/null; then
  fail "kernel_blob_not_in_git"
else
  pass "kernel_blob_not_in_git"
fi

echo "== extract refuses RYOKU_VERIFY_GPG=0 (temp fixtures only) =="
FAKE_ISO="$TEMP_RUN/alpine-virt-3.21.9-x86_64.iso"
echo 'not-a-real-iso' >"$FAKE_ISO"
set +e
out="$(RYOKU_KERNEL_EXTRACT_EXECUTE=1 RYOKU_VERIFY_GPG=0 "$EXTRACT" 2>&1)"
rc=$?
set -e
if [[ "$rc" -ne 0 ]] && echo "$out" | grep -Eqi 'VERIFY_GPG|refusing real extract'; then
  pass "extract_rejects_gpg_off"
else
  fail "extract_rejects_gpg_off (rc=$rc)"
  echo "$out" | tail -15
fi

echo "== extract refuses without SHA/GPG sidecars (even with VERIFY_GPG=1) =="
# ISO present in temp run/; no sidecars — must refuse before any write.
rm -f "$TEMP_RUN"/*.sha256 "$TEMP_RUN"/*.asc "$TEMP_RUN"/ncopa.asc \
  "$TEMP_RUN"/ryoku-boot-seed-vmlinuz 2>/dev/null || true
set +e
out="$(RYOKU_KERNEL_EXTRACT_EXECUTE=1 RYOKU_VERIFY_GPG=1 "$EXTRACT" 2>&1)"
rc=$?
set -e
if [[ "$rc" -ne 0 ]] && echo "$out" | grep -Eqi 'sidecar|missing|GPG|SHA|ncopa'; then
  pass "extract_requires_integrity_sidecars"
else
  fail "extract_requires_integrity_sidecars (rc=$rc)"
  echo "$out" | tail -15
fi

echo "== extract refuses destination symlink (temp file outside lab) =="
OUT_LINK="$TEMP_RUN/ryoku-boot-seed-vmlinuz"
OUTSIDE="$TMPROOT/outside-vmlinuz"
echo x >"$OUTSIDE"
rm -f "$OUT_LINK"
ln -s "$OUTSIDE" "$OUT_LINK"
echo 'fake' >"$FAKE_ISO"
set +e
out="$(RYOKU_KERNEL_EXTRACT_EXECUTE=1 RYOKU_VERIFY_GPG=1 "$EXTRACT" 2>&1)"
rc=$?
set -e
rm -f "$OUT_LINK" "$FAKE_ISO"
if [[ "$rc" -ne 0 ]] \
  && echo "$out" | grep -Eqi 'refusing destination symlink|destination symlink' \
  && [[ "$(cat "$OUTSIDE")" == "x" ]]; then
  pass "extract_rejects_dest_symlink"
else
  fail "extract_rejects_dest_symlink (rc=$rc)"
  echo "$out" | tail -20
fi

echo "== extract refuses ISO symlink escaping lab run =="
echo 'outside-iso' >"$TMPROOT/escape.iso"
rm -f "$FAKE_ISO"
ln -s "$TMPROOT/escape.iso" "$FAKE_ISO"
set +e
out="$(RYOKU_KERNEL_EXTRACT_EXECUTE=1 RYOKU_VERIFY_GPG=1 "$EXTRACT" 2>&1)"
rc=$?
set -e
rm -f "$FAKE_ISO"
if [[ "$rc" -ne 0 ]] && echo "$out" | grep -Eqi 'symlink|outside|canonical|lab'; then
  pass "extract_rejects_iso_symlink_escape"
else
  fail "extract_rejects_iso_symlink_escape (rc=$rc)"
  echo "$out" | tail -15
fi

echo "== real repo ISO/kernel untouched =="
real_iso_after=0
real_vmlinuz_after=0
[[ -e "$REAL_ISO" || -L "$REAL_ISO" ]] && real_iso_after=1
[[ -e "$REAL_VMLINUZ" || -L "$REAL_VMLINUZ" ]] && real_vmlinuz_after=1
real_iso_sha_after=""
real_vmlinuz_sha_after=""
[[ -f "$REAL_ISO" && ! -L "$REAL_ISO" ]] && real_iso_sha_after="$(sha256sum "$REAL_ISO" | awk '{print $1}')"
[[ -f "$REAL_VMLINUZ" && ! -L "$REAL_VMLINUZ" ]] && real_vmlinuz_sha_after="$(sha256sum "$REAL_VMLINUZ" | awk '{print $1}')"
if [[ "$real_iso_before" == "$real_iso_after" ]] \
  && [[ "$real_vmlinuz_before" == "$real_vmlinuz_after" ]] \
  && [[ "$real_iso_sha_before" == "$real_iso_sha_after" ]] \
  && [[ "$real_vmlinuz_sha_before" == "$real_vmlinuz_sha_after" ]]; then
  pass "real_lab_artifacts_untouched"
else
  fail "real_lab_artifacts_untouched"
fi

echo "== harness all excludes T3 =="
if grep -E 'if which == "boot-seed" \|\| which == "t3"' \
  "$REPO_ROOT/zaquion-core/ryoku-virtlab/src/main.rs" | grep -q 'all'; then
  fail "all_excludes_t3 (all leaked into boot-seed if)"
elif grep -E 'if which == "boot-seed" \|\| which == "t3"' \
  "$REPO_ROOT/zaquion-core/ryoku-virtlab/src/main.rs" >/dev/null \
  && grep -A1 'if which == "boot-seed" || which == "t3"' \
    "$REPO_ROOT/zaquion-core/ryoku-virtlab/src/main.rs" | grep -q 'run_boot_seed'; then
  pass "all_excludes_t3"
else
  fail "all_excludes_t3"
fi

echo "== unauthorized T3 gate (RYOKU_T3_EXECUTE unset / not 1) =="
if grep -q 'RYOKU_T3_EXECUTE' "$REPO_ROOT/zaquion-core/ryoku-virtlab/src/boot_seed.rs" \
  && grep -q 't3_guest_execute_authorized' "$REPO_ROOT/zaquion-core/ryoku-virtlab/src/boot_seed.rs"; then
  (
    cd "$REPO_ROOT/zaquion-core"
    unset RYOKU_T3_EXECUTE || true
    cargo test -q -p ryoku-virtlab t3_execute_gate_defaults_closed -- --nocapture
  ) && pass "unauthorized_t3_gate" || fail "unauthorized_t3_gate"
else
  fail "unauthorized_t3_gate (helper missing)"
fi

echo
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
