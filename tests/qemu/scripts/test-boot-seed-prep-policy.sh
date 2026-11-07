#!/usr/bin/env bash
# Policy mocks for Mission 009 / 009.5 Boot Seed prep (no ISO download, no T3).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LAB="$ROOT/tests/qemu"
RUN="$LAB/run"
EXTRACT="$ROOT/tests/qemu/scripts/extract-boot-seed-kernel.sh"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/ryoku-prep-policy.XXXXXX")"
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

echo "== extract-boot-seed-kernel dry-run (no download) =="
dry_out="$(RYOKU_KERNEL_EXTRACT_EXECUTE=0 "$EXTRACT" 2>&1)"
if echo "$dry_out" | grep -q 'DRY-RUN' \
  && ! echo "$dry_out" | grep -Eqi 'curl |wget |https://'; then
  pass "kernel_extract_dry_run_no_download"
else
  fail "kernel_extract_dry_run_no_download"
fi

echo "== prep-boot-seed-artifacts dry-run =="
if RYOKU_BOOT_SEED_PREP_EXECUTE=0 "$ROOT/tests/qemu/scripts/prep-boot-seed-artifacts.sh" \
  | grep -q 'DRY-RUN'; then
  pass "artifact_prep_dry_run"
else
  fail "artifact_prep_dry_run"
fi

echo "== initramfs builder dry-run =="
if RYOKU_INITRAMFS_EXECUTE=0 "$ROOT/tests/qemu/scripts/build-boot-seed-initramfs.sh" \
  | grep -q 'DRY-RUN'; then
  pass "initramfs_dry_run"
else
  fail "initramfs_dry_run"
fi

echo "== ALLOW_DYNAMIC blocked =="
if ! RYOKU_INITRAMFS_ALLOW_DYNAMIC=1 "$ROOT/tests/qemu/scripts/build-boot-seed-initramfs.sh" \
  >/tmp/ryoku-allow-dyn.out 2>/tmp/ryoku-allow-dyn.err; then
  if grep -qi 'blocked\|ALLOW_DYNAMIC' /tmp/ryoku-allow-dyn.err /tmp/ryoku-allow-dyn.out; then
    pass "allow_dynamic_blocked"
  else
    fail "allow_dynamic_blocked (exit nonzero but message missing)"
  fi
else
  fail "allow_dynamic_blocked (should exit nonzero)"
fi

echo "== workflow_dispatch gate present =="
WF="$ROOT/.github/workflows/boot-seed-t3.yml"
if [[ -f "$WF" ]] \
  && grep -q 'workflow_dispatch' "$WF" \
  && grep -q "confirm == 'RUN'" "$WF" \
  && grep -q 'RYOKU_T3_EXECUTE' "$WF" \
  && ! grep -qE '^\s+push:' "$WF" \
  && ! grep -qE '^\s+pull_request:' "$WF"; then
  pass "workflow_manual_gate"
else
  fail "workflow_manual_gate"
fi

echo "== no kernel blob in git =="
if git -C "$ROOT" ls-files 'tests/qemu/run/*' 2>/dev/null | grep -E 'vmlinuz|cpio|\.iso$' >/dev/null; then
  fail "kernel_blob_not_in_git"
else
  pass "kernel_blob_not_in_git"
fi

echo "== extract refuses RYOKU_VERIFY_GPG=0 =="
FAKE_ISO="$RUN/alpine-virt-3.21.9-x86_64.iso"
CREATED_ISO=0
if [[ ! -f "$FAKE_ISO" ]]; then
  echo 'not-a-real-iso' >"$FAKE_ISO"
  CREATED_ISO=1
fi
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
if [[ "$CREATED_ISO" == "1" ]]; then rm -f "$FAKE_ISO"; fi

echo "== extract refuses destination symlink (temp file outside lab) =="
OUT_LINK="$RUN/ryoku-boot-seed-vmlinuz"
OUTSIDE="$TMPROOT/outside-vmlinuz"
echo x >"$OUTSIDE"
rm -f "$OUT_LINK"
ln -s "$OUTSIDE" "$OUT_LINK"
# Dest symlink is checked after ISO existence and before SHA/GPG — only need a regular ISO file.
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

echo "== harness all excludes T3 =="
if grep -E 'if which == "boot-seed" \|\| which == "t3"' \
  "$ROOT/zaquion-core/ryoku-virtlab/src/main.rs" | grep -q 'all'; then
  fail "all_excludes_t3 (all leaked into boot-seed if)"
elif grep -E 'if which == "boot-seed" \|\| which == "t3"' \
  "$ROOT/zaquion-core/ryoku-virtlab/src/main.rs" >/dev/null \
  && grep -A1 'if which == "boot-seed" || which == "t3"' \
    "$ROOT/zaquion-core/ryoku-virtlab/src/main.rs" | grep -q 'run_boot_seed'; then
  pass "all_excludes_t3"
else
  fail "all_excludes_t3"
fi

echo "== unauthorized T3 gate (RYOKU_T3_EXECUTE unset / not 1) =="
# Source-level helper + unit test: env must be exactly 1; all≠T3 already checked above.
if grep -q 'RYOKU_T3_EXECUTE' "$ROOT/zaquion-core/ryoku-virtlab/src/boot_seed.rs" \
  && grep -q 't3_guest_execute_authorized' "$ROOT/zaquion-core/ryoku-virtlab/src/boot_seed.rs"; then
  (
    cd "$ROOT/zaquion-core"
    unset RYOKU_T3_EXECUTE || true
    cargo test -q -p ryoku-virtlab t3_execute_gate_defaults_closed -- --nocapture
  ) && pass "unauthorized_t3_gate" || fail "unauthorized_t3_gate"
else
  fail "unauthorized_t3_gate (helper missing)"
fi

echo
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
