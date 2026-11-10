#!/usr/bin/env bash
# HM host module + bootstrap preflight tests (no QEMU, no guest).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BOOTSTRAP="$ROOT/distro/scripts/ryoku-bootstrap"
FIX="$ROOT/distro/tests/fixtures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -rf "$FIX/pretend-debian/usr" "$FIX/pretend-debian/var" "$FIX/pretend-debian/etc/nix" 2>/dev/null || true' EXIT

pass=0
fail=0

check() {
  local name=$1
  shift
  if "$@"; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name" >&2
    fail=$((fail + 1))
  fi
}

check_fail() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $name (expected non-zero)" >&2
    fail=$((fail + 1))
  else
    echo "PASS: $name"
    pass=$((pass + 1))
  fi
}

chmod +x "$BOOTSTRAP" \
  "$ROOT/distro/session/ryoku-niri-session" \
  "$ROOT/distro/session/ryoku-hyprland-session" 2>/dev/null || true

# --- Flake discovers committed ryoku host ------------------------------------
check "hosts/ryoku/default.nix exists" test -f "$ROOT/distro/flake/hosts/ryoku/default.nix"
check "ryoku host username" grep -q 'username = "ryoku"' "$ROOT/distro/flake/hosts/ryoku/default.nix"
check "ryoku host home" grep -q 'homeDirectory = "/home/ryoku"' "$ROOT/distro/flake/hosts/ryoku/default.nix"
check "ryoku jarvis default false" grep -q 'jarvis = false' "$ROOT/distro/flake/hosts/ryoku/default.nix"

# --- Generate alice + ryoku into isolated flake-dir --------------------------
FLAKE_TMP="$TMP/flake"
cp -a "$ROOT/distro/flake/." "$FLAKE_TMP/"
# Drop example host copies we will regenerate
rm -rf "$FLAKE_TMP/hosts/alice" 2>/dev/null || true

check "apply fixture writes alice host" \
  "$BOOTSTRAP" --apply --sysroot "$FIX/pretend-debian" --user alice --yes \
  --flake-dir "$FLAKE_TMP" \
  --log-dir "$TMP/logs-alice" --backup-dir "$TMP/bak-alice" \
  --skip-apt --skip-nix --skip-hm

ALICE_HOST="$FLAKE_TMP/hosts/alice/default.nix"
check "alice host file exists" test -f "$ALICE_HOST"
check "alice username" grep -q 'username = "alice"' "$ALICE_HOST"
check "alice home /home/alice" grep -q 'homeDirectory = "/home/alice"' "$ALICE_HOST"
check_fail "alice must not use /home/ryoku" grep -q 'homeDirectory = "/home/ryoku"' "$ALICE_HOST"

check "apply fixture writes ryoku host" \
  "$BOOTSTRAP" --apply --sysroot "$FIX/pretend-debian" --user ryoku --yes \
  --flake-dir "$FLAKE_TMP" \
  --log-dir "$TMP/logs-ryoku" --backup-dir "$TMP/bak-ryoku" \
  --skip-apt --skip-nix --skip-hm \
  --profile full --visual ultra --shell-style islands

RYOKU_HOST="$FLAKE_TMP/hosts/ryoku/default.nix"
check "ryoku regenerated host exists" test -f "$RYOKU_HOST"
check "ryoku home still /home/ryoku" grep -q 'homeDirectory = "/home/ryoku"' "$RYOKU_HOST"
check "ryoku profile full" grep -q 'edition = "full"' "$RYOKU_HOST"
check "ryoku visual ultra" grep -q 'visual = "ultra"' "$RYOKU_HOST"
check "ryoku shell islands" grep -q 'shellStyle = "islands"' "$RYOKU_HOST"
check "ryoku compositor default hyprland" grep -q 'compositor = "hyprland"' "$RYOKU_HOST"

# Distinct homes
if [[ -f "$ALICE_HOST" && -f "$RYOKU_HOST" ]]; then
  alice_home=$(grep homeDirectory "$ALICE_HOST" | head -1 || true)
  ryoku_home=$(grep homeDirectory "$RYOKU_HOST" | head -1 || true)
  if [[ -n "$alice_home" && -n "$ryoku_home" && "$alice_home" != "$ryoku_home" ]]; then
    echo "PASS: alice and ryoku homes distinct"
    pass=$((pass + 1))
  else
    echo "FAIL: alice and ryoku homes not distinct ('$alice_home' vs '$ryoku_home')" >&2
    fail=$((fail + 1))
  fi
else
  echo "FAIL: missing alice or ryoku host for distinct-home check" >&2
  fail=$((fail + 1))
fi

# Jarvis off unless --jarvis
check "alice jarvis false by default" grep -q 'jarvis = false' "$ALICE_HOST"

"$BOOTSTRAP" --apply --sysroot "$FIX/pretend-debian" --user alice --yes --jarvis \
  --flake-dir "$FLAKE_TMP" \
  --log-dir "$TMP/logs-j" --backup-dir "$TMP/bak-j" \
  --skip-apt --skip-nix --skip-hm >/dev/null
check "alice jarvis true with --jarvis" grep -q 'jarvis = true' "$ALICE_HOST"

# --- Dry-run is no-op for host tree ------------------------------------------
BEFORE=$(find "$FLAKE_TMP/hosts" -type f -name default.nix -print0 | sort -z | xargs -0 sha256sum)
"$BOOTSTRAP" --dry-run --sysroot "$FIX/pretend-debian" --user bob \
  --flake-dir "$FLAKE_TMP" \
  --log-dir "$TMP/logs-dry" --backup-dir "$TMP/bak-dry" >/dev/null
AFTER=$(find "$FLAKE_TMP/hosts" -type f -name default.nix -print0 | sort -z | xargs -0 sha256sum)
if [[ "$BEFORE" == "$AFTER" ]] && [[ ! -f "$FLAKE_TMP/hosts/bob/default.nix" ]]; then
  echo "PASS: dry-run did not write bob host (no-op)"
  pass=$((pass + 1))
else
  echo "FAIL: dry-run mutated hosts/" >&2
  fail=$((fail + 1))
fi

# --- flake.nix must not hardcode only /home/ryoku for all attrs --------------
if grep -n 'homeConfigurations\.ryoku = mkHome' "$ROOT/distro/flake/flake.nix"; then
  echo "FAIL: flake still hardcodes homeConfigurations.ryoku = mkHome" >&2
  fail=$((fail + 1))
else
  echo "PASS: flake uses hosts/ discovery (no fixed ryoku-only mkHome)"
  pass=$((pass + 1))
fi
check "flake genAttrs hosts" grep -q 'genAttrs hostNames' "$ROOT/distro/flake/flake.nix"
check_fail "no gitignored overlay reference in flake" grep -q 'ryoku-user.nix' "$ROOT/distro/flake/flake.nix"

# --- GDM / Hyprland primary + Niri recovery ---------------------------------
check "GDM Hyprland Exec" grep -q '^Exec=ryoku-hyprland-session' "$ROOT/distro/session/ryoku-hyprland.desktop"
check "wrapper mentions Hyprland" grep -q 'Hyprland' "$ROOT/distro/session/ryoku-hyprland-session"
check "GDM Niri recovery Exec" grep -q '^Exec=ryoku-niri-session' "$ROOT/distro/session/ryoku-niri.desktop"
check "wrapper mentions niri" grep -q 'niri' "$ROOT/distro/session/ryoku-niri-session"
opens=$(grep -o '{' "$ROOT/distro/flake/home/niri.nix" | wc -l)
closes=$(grep -o '}' "$ROOT/distro/flake/home/niri.nix" | wc -l)
check "niri.nix brace balance" test "$opens" -eq "$closes"
hopens=$(grep -o '{' "$ROOT/distro/flake/home/hyprland.nix" | wc -l)
hcloses=$(grep -o '}' "$ROOT/distro/flake/home/hyprland.nix" | wc -l)
check "hyprland.nix brace balance" test "$hopens" -eq "$hcloses"
check "bootstrap --compositor flag" grep -q -- '--compositor' "$BOOTSTRAP"
check "alice host includes compositor" grep -q 'compositor =' "$ALICE_HOST"

# --- Refuse NixOS ------------------------------------------------------------
check_fail "refuse NixOS dry-run" \
  "$BOOTSTRAP" --dry-run --sysroot "$FIX/pretend-nixos" --user alice \
  --flake-dir "$FLAKE_TMP" --log-dir "$TMP/nx" --backup-dir "$TMP/nxb"

# --- No gitignored overlay dependency ----------------------------------------
check_fail "bootstrap must not write .ryoku-user.nix" \
  grep -q '\.ryoku-user\.nix' "$BOOTSTRAP"
if grep -q 'hosts/\$TARGET_USER/default.nix' "$BOOTSTRAP"; then
  echo "PASS: bootstrap writes hosts/<user>/default.nix"
  pass=$((pass + 1))
else
  echo "FAIL: bootstrap missing hosts/<user>/default.nix path" >&2
  fail=$((fail + 1))
fi

echo
echo "Summary: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
