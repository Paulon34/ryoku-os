#!/usr/bin/env bash
# Guard: dms ipc always execs bare "qs" (DankMaterialShell shell.go).
# A store dms without Quickshell on PATH reproduces the guest SSH failure:
#   exec: "qs": executable file not found in $PATH
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DMS_MODULE="$ROOT/distro/flake/home/dms.nix"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

grep -Fq 'writeShellScriptBin "dms"' "$DMS_MODULE" ||
  fail "missing dms wrapper that prepends qs"
grep -Fq 'dmsRuntimePath' "$DMS_MODULE" ||
  fail "missing shared dmsRuntimePath"
# Simulate the Go LookPath failure mode with a fake dms that execs qs.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '#!/bin/sh' 'exec qs "$@"' >"$TMP/fake-dms"
chmod +x "$TMP/fake-dms"
printf '%s\n' '#!/bin/sh' 'echo qs-ok' >"$TMP/qs"
chmod +x "$TMP/qs"

# Without qs on PATH → failure (guest SSH symptom).
if env -i PATH=/usr/bin:/bin "$TMP/fake-dms" ipc call bar status index 0 >/dev/null 2>&1; then
  fail "expected qs missing without Quickshell on PATH"
fi
pass "reproduced qs-missing without PATH"

# With qs on PATH → success (what dmsRuntimePath / wrapper must provide).
out=$(env -i PATH="$TMP:/usr/bin:/bin" "$TMP/fake-dms" ipc call bar status index 0)
[[ "$out" == "qs-ok" ]] || fail "qs not found with PATH prepend"
pass "qs resolves when runtime PATH includes Quickshell"

# Document correct IPC (do not invent Instance+Config together).
# Canonical from DMS 1.5.3 DMSShellIPC.qml target bar:
#   dms ipc call bar status index 0
#   dms ipc call bar reveal index 0
# Wrong: mixing qs ipc --pid with -p (Option Group Instance vs Config).
grep -Fq 'ryoku-dms-ipc' "$ROOT/distro/flake/home/niri.nix" ||
  fail "session binds should keep ryoku-dms-ipc"
pass "IPC documentation guards"

echo "All dms ipc PATH regressions passed."
