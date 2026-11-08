#!/usr/bin/env bash
# Guard the Quattro barConfigs array merge (DMS 1.5.3 SettingsData.find by id).
# Reproduces the object-map bug that left the Quattro strip unconfigured.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

command -v jq >/dev/null 2>&1 || fail "jq required"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Broken shape previously emitted by xdg.configFile JSON (object map).
printf '%s\n' '{"cornerRadius":8,"barConfigs":{"default":{"transparency":0.96}}}' >"$TMP/broken.json"
jq -e '.barConfigs | type == "object"' "$TMP/broken.json" >/dev/null ||
  fail "fixture broken shape"
# DMS finds by array id — object maps yield no default bar.
if jq -e '(.barConfigs // []) | type == "array" and (map(select(.id=="default"))|length)>0' "$TMP/broken.json" >/dev/null 2>&1; then
  fail "object-map barConfigs must not look like a valid DMS array"
fi
pass "object-map barConfigs rejected"

# Correct merge (mirrors distro/flake/home/dms.nix apply-ryoku-dms-bar).
printf '%s\n' '{"cornerRadius":16,"barConfigs":[{"id":"default","transparency":0.5}]}' >"$TMP/settings.json"
printf '%s\n' '{"cornerRadius":8,"popupTransparency":0.97}' >"$TMP/patch.json"
printf '%s\n' '{"id":"default","transparency":0.96,"squareCorners":true,"leftWidgets":["launcherButton","workspaceSwitcher"],"centerWidgets":["clock"],"rightWidgets":["systemTray","notificationButton","controlCenterButton","battery"]}' >"$TMP/bar.json"

jq -s '
  .[0] as $s | .[1] as $p | .[2] as $bar |
  ($s + $p) |
  .barConfigs = (
    ((.barConfigs // []) | if type == "array" then . else [] end) as $cfgs |
    if ($cfgs | map(select(.id == "default")) | length) > 0 then
      $cfgs | map(if .id == "default" then . + $bar else . end)
    else
      $cfgs + [$bar]
    end
  )
' "$TMP/settings.json" "$TMP/patch.json" "$TMP/bar.json" >"$TMP/out.json"

jq -e '.cornerRadius == 8' "$TMP/out.json" >/dev/null || fail "style patch not merged"
jq -e '.barConfigs | type == "array"' "$TMP/out.json" >/dev/null || fail "barConfigs not array"
jq -e '.barConfigs[] | select(.id=="default") | .transparency == 0.96' "$TMP/out.json" >/dev/null ||
  fail "default bar transparency not applied"
jq -e '.barConfigs[] | select(.id=="default") | .leftWidgets | index("workspaceSwitcher")' "$TMP/out.json" >/dev/null ||
  fail "workspaceSwitcher missing from Quattro leftWidgets"
jq -e '.barConfigs[] | select(.id=="default") | .squareCorners == true' "$TMP/out.json" >/dev/null ||
  fail "Quattro squareCorners missing"
pass "Quattro barConfigs array merge"

# Empty / missing barConfigs → insert default.
printf '%s\n' '{"cornerRadius":8}' >"$TMP/empty.json"
jq -s '
  .[0] as $s | .[1] as $p | .[2] as $bar |
  ($s + $p) |
  .barConfigs = (
    ((.barConfigs // []) | if type == "array" then . else [] end) as $cfgs |
    if ($cfgs | map(select(.id == "default")) | length) > 0 then
      $cfgs | map(if .id == "default" then . + $bar else . end)
    else
      $cfgs + [$bar]
    end
  )
' "$TMP/empty.json" "$TMP/patch.json" "$TMP/bar.json" >"$TMP/inserted.json"
jq -e '.barConfigs | length == 1 and .[0].id == "default"' "$TMP/inserted.json" >/dev/null ||
  fail "missing barConfigs should insert default"
pass "insert default bar when absent"

# Coerce object map → array default (recovery path).
printf '%s\n' '{"barConfigs":{"default":{"transparency":0.1}}}' >"$TMP/obj.json"
jq -s '
  .[0] as $s | .[1] as $p | .[2] as $bar |
  ($s + $p) |
  .barConfigs = (
    ((.barConfigs // []) | if type == "array" then . else [] end) as $cfgs |
    if ($cfgs | map(select(.id == "default")) | length) > 0 then
      $cfgs | map(if .id == "default" then . + $bar else . end)
    else
      $cfgs + [$bar]
    end
  )
' "$TMP/obj.json" "$TMP/patch.json" "$TMP/bar.json" >"$TMP/recovered.json"
jq -e '.barConfigs | type == "array" and length == 1 and .[0].transparency == 0.96' "$TMP/recovered.json" >/dev/null ||
  fail "object-map barConfigs should be replaced with Quattro array default"
pass "object-map barConfigs recovered to array"

echo "All DMS bar merge regressions passed."
