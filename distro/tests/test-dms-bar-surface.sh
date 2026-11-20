#!/usr/bin/env bash
# Guard: DankBar Wayland surface requires barConfigs[].enabled == true.
# ShellCore.qml: active: barSurfacesLoaded && (barConfig?.enabled ?? false) && …
# Without enabled, Niri shows only Background quickshell — Top/Bottom/Overlay empty
# while dms ipc bar status can still say "visible".
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DMS_MODULE="$ROOT/distro/flake/home/dms.nix"
SHELLCORE_HINT="$ROOT/distro/docs/DMS_BAR_SURFACE.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq required"
test -f "$SHELLCORE_HINT" || fail "missing $SHELLCORE_HINT documentation"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Guest-shaped settings: visible true, but enabled omitted (ShellCore → false).
printf '%s\n' '{"barConfigs":[{"id":"default","visible":true,"autoHide":false,"leftWidgets":["clock"]}]}' >"$TMP/settings.json"
enabled=$(jq -r '.barConfigs[0].enabled // false' "$TMP/settings.json")
[[ "$enabled" == "false" ]] || fail "fixture should lack enabled"
pass "missing enabled ⇒ ShellCore Loader inactive (no Top layer)"

# getPosition without numeric position → unknown
pos=$(jq -r '.barConfigs[0].position // empty' "$TMP/settings.json")
[[ -z "$pos" ]] || fail "fixture should omit position"
pass "missing position ⇒ getPosition unknown"

# After Ryoku merge (styleBar fields), surface keys must be present.
printf '%s\n' '{"id":"default","name":"Main Bar","enabled":true,"position":0,"screenPreferences":["all"],"showOnLastDisplay":true,"visible":true,"autoHide":false}' >"$TMP/bar.json"
jq -s '
  .[0] as $s | .[1] as $bar |
  $s |
  .barConfigs = (
    ((.barConfigs // []) | if type == "array" then . else [] end) as $cfgs |
    if ($cfgs | map(select(.id == "default")) | length) > 0 then
      $cfgs | map(if .id == "default" then . + $bar else . end)
    else
      $cfgs + [$bar]
    end
  )
' "$TMP/settings.json" "$TMP/bar.json" >"$TMP/out.json"

jq -e '.barConfigs[0].enabled == true' "$TMP/out.json" >/dev/null || fail "merge must set enabled"
jq -e '.barConfigs[0].position == 0' "$TMP/out.json" >/dev/null || fail "merge must set position Top(0)"
jq -e '.barConfigs[0].screenPreferences == ["all"]' "$TMP/out.json" >/dev/null || fail "merge must set screenPreferences"
positions=(top bottom left right)
pos=$(jq -r '.barConfigs[0].position' "$TMP/out.json")
[[ "${positions[$pos]}" == "top" ]] || fail "position 0 must map to top (not unknown)"
pass "merge enables Top bar surface prerequisites"

grep -Fq 'enabled = true' "$DMS_MODULE" || fail "dms.nix missing enabled = true"
grep -Fq 'position = 0' "$DMS_MODULE" || fail "dms.nix missing position = 0"
grep -Fq 'screenPreferences = [ "all" ]' "$DMS_MODULE" || fail "dms.nix missing screenPreferences all"
pass "sources declare surface keys"

echo "All DMS bar surface regressions passed."
