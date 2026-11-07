#!/usr/bin/env bash
# Policy mocks for Mission 009 Boot Seed prep (no ISO download, no T3).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

echo "== extract-boot-seed-kernel dry-run =="
if RYOKU_KERNEL_EXTRACT_EXECUTE=0 "$ROOT/tests/qemu/scripts/extract-boot-seed-kernel.sh" \
  | grep -q 'DRY-RUN'; then
  pass "kernel_extract_dry_run"
else
  fail "kernel_extract_dry_run"
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

echo
echo "Summary: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
