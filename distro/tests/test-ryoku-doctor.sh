#!/usr/bin/env bash
# Static + local checks for ryoku-doctor / build-info (no guest session required).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DOC="$ROOT/distro/scripts/ryoku-doctor"
fail=0

pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

[[ -x "$DOC" ]] || fail_msg "ryoku-doctor not executable"
bash -n "$DOC" || fail_msg "ryoku-doctor bash -n"

grep -Fq 'build-info.json' "$DOC" || fail_msg "doctor must read build-info.json"
grep -Fq '.local/state/ryoku/build-info.json' "$DOC" || fail_msg "doctor must prefer XDG state path"
grep -Fq 'gitCommit' "$DOC" || fail_msg "doctor must compare gitCommit"
grep -Fq 'windowrulev2' "$DOC" || fail_msg "doctor must flag windowrulev2"
# Only active directives are errors; comments mentioning obsolete syntax are harmless.
grep -Fq "^[[:space:]]*windowrulev2[[:space:]]*=" "$DOC" \
  || fail_msg "doctor must anchor deprecated rule detection to directives"
grep -Fq "^[[:space:]]*windowrule[[:space:]]*=" "$DOC" \
  || fail_msg "doctor must anchor classic windowrule detection to directives"
grep -Fq 'home-path/bin/niri' "$DOC" \
  || fail_msg "doctor must detect HM Niri outside SSH PATH"
grep -Fq 'home-path/bin/ryoku-settings' "$DOC" \
  || fail_msg "doctor must detect HM Settings outside SSH PATH"
grep -Fq 'STALE HM' "$DOC" || fail_msg "doctor must report STALE HM"

# build-info module — mutable state only (no xdg.configFile conflict)
BI="$ROOT/distro/flake/home/build-info.nix"
[[ -f "$BI" ]] || fail_msg "missing build-info.nix"
grep -Fq 'gitCommit' "$BI" || fail_msg "build-info must stamp gitCommit"
grep -Fq 'hmGeneration' "$BI" || fail_msg "build-info must stamp hmGeneration"
grep -Fq 'ryoku-doctor' "$BI" || fail_msg "build-info must package ryoku-doctor"
grep -Fq '.local/state/ryoku' "$BI" || fail_msg "build-info must write under XDG state"
! grep -Eq 'xdg\.configFile\."ryoku/build-info' "$BI" \
  || fail_msg "build-info must NOT use xdg.configFile for mutable stamp"

# Run doctor (expected WARN/OK on CI host — must not crash)
set +e
out=$("$DOC" 2>&1)
rc=$?
set -e
echo "$out" | head -40
if [[ "$rc" -gt 1 ]]; then
  fail_msg "ryoku-doctor exited $rc (expected 0 or 1)"
else
  pass "ryoku-doctor ran (exit $rc)"
fi
echo "$out" | grep -Eq 'RESULT: (OK|FAIL)' || fail_msg "doctor missing RESULT line"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (ryoku-doctor)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
