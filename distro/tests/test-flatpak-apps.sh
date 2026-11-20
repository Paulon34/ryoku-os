#!/usr/bin/env bash
# Static checks for Flatpak manifests + sync dry-run (no network install).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0
pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

[[ -f "$ROOT/distro/flatpak/apps-minimal.txt" ]] && pass "apps-minimal.txt" || fail_msg "missing apps-minimal"
[[ -f "$ROOT/distro/flatpak/apps-full.txt" ]] && pass "apps-full.txt" || fail_msg "missing apps-full"
[[ -x "$ROOT/distro/scripts/ryoku-flatpak-sync" ]] && pass "ryoku-flatpak-sync exec" || fail_msg "flatpak-sync not executable"
[[ -x "$ROOT/distro/scripts/ryoku-pkg-helper" ]] && pass "ryoku-pkg-helper exec" || fail_msg "pkg-helper not executable"
[[ -f "$ROOT/distro/polkit/org.ryoku.pkg.policy" ]] && pass "pkg polkit policy" || fail_msg "missing pkg policy"

# Full profile IDs — structure + known Flathub IDs
need_full=(com.github.tchx84.Flatseal org.localsend.localsend_app org.telegram.desktop)
for id in "${need_full[@]}"; do
  grep -Eq "^${id}$" "$ROOT/distro/flatpak/apps-full.txt" \
    && pass "full has $id" \
    || fail_msg "apps-full missing $id"
  [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(\.[A-Za-z0-9][A-Za-z0-9._-]*)+$ ]] \
    && pass "id shape $id" \
    || fail_msg "bad id shape $id"
done

# Sorted unique in full list
mapfile -t ids < <(grep -vE '^\s*(#|$)' "$ROOT/distro/flatpak/apps-full.txt")
mapfile -t sorted < <(printf '%s\n' "${ids[@]}" | sort -u)
if [[ "${ids[*]}" == "${sorted[*]}" ]]; then
  pass "apps-full sorted unique"
else
  fail_msg "apps-full must be sorted unique (got: ${ids[*]})"
fi

# list-declared
out=$("$ROOT/distro/scripts/ryoku-flatpak-sync" --list-declared --profile full)
echo "$out" | grep -q 'org.telegram.desktop' && pass "list-declared full" || fail_msg "list-declared missing telegram"
min_out=$("$ROOT/distro/scripts/ryoku-flatpak-sync" --list-declared --profile minimal)
if [[ -z "$(echo "$min_out" | tr -d '[:space:]')" ]]; then
  pass "list-declared minimal empty"
else
  fail_msg "minimal should declare no flatpaks by default (got: $min_out)"
fi

# dry-run (no network mutation)
set +e
sync_out=$("$ROOT/distro/scripts/ryoku-flatpak-sync" --dry-run --profile full 2>&1)
sync_rc=$?
set -e
[[ "$sync_rc" -eq 0 ]] && pass "flatpak-sync dry-run full" || fail_msg "flatpak-sync dry-run failed: $sync_rc"
echo "$sync_out" | grep -Eq 'flathub|Flatpak|dry-run' && pass "dry-run mentions flathub/plan" || fail_msg "dry-run output unexpected"

# pkg-helper refuses unknown verb / invalid names (no root needed for validation path that dies early)
set +e
"$ROOT/distro/scripts/ryoku-pkg-helper" not-a-verb >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "pkg-helper rejects unknown verb" || fail_msg "pkg-helper should reject unknown verb"
"$ROOT/distro/scripts/ryoku-pkg-helper" apt-install 'Evil;rm' >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "pkg-helper rejects bad apt name" || fail_msg "pkg-helper should reject bad apt name"
"$ROOT/distro/scripts/ryoku-pkg-helper" flatpak-install 'not-an-id' >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "pkg-helper rejects bad flatpak id" || fail_msg "pkg-helper should reject bad flatpak id"
set -e

# Settings wiring
grep -Fq 'DesktopAppsModel' "$ROOT/distro/apps/ryoku-settings/src/main.cpp" \
  && pass "Settings wires DesktopAppsModel" || fail_msg "main.cpp missing DesktopAppsModel"
grep -Fq 'desktopApps' "$ROOT/distro/apps/ryoku-settings/qml/pages/AppsPage.qml" \
  && pass "AppsPage uses desktopApps" || fail_msg "AppsPage missing desktopApps"
grep -Fq 'install_flatpak' "$ROOT/distro/scripts/ryoku-bootstrap" \
  && pass "bootstrap calls install_flatpak" || fail_msg "bootstrap missing install_flatpak"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (flatpak-apps)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
