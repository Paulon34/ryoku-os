#!/usr/bin/env bash
# Static Debian SDDM Astronaut port checks (no root or display required).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
failed=0
pass() { echo "PASS_STATIC: $*"; }
fail() { echo "FAIL: $*" >&2; failed=$((failed + 1)); }

for p in \
  distro/sddm/astronaut-overlay/Main.qml \
  distro/sddm/astronaut-overlay/Clock.qml \
  distro/sddm/astronaut-overlay/SystemButtons.qml \
  distro/scripts/ryoku-sddm \
  distro/scripts/ryoku-sddm-wallpaper \
  distro/polkit/org.ryoku.sddm.wallpaper.policy \
  distro/docs/SDDM_DEBIAN.md \
  distro/LICENSES/GPL-3.0-or-later.txt; do
  [[ -f "$ROOT/$p" ]] && pass "$p" || fail "missing $p"
done

bash -n "$ROOT/distro/scripts/ryoku-sddm" &&
  pass "theme stage/rollback bash syntax" || fail "stage script syntax"
bash -n "$ROOT/distro/scripts/ryoku-sddm-wallpaper" &&
  pass "privileged wallpaper helper bash syntax" || fail "helper syntax"
python3 - "$ROOT/distro/polkit/org.ryoku.sddm.wallpaper.policy" <<'PY' ||
  fail "polkit action XML parse"
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
assert root.tag == "policyconfig"
actions = root.findall("action")
assert len(actions) == 1 and actions[0].attrib["id"] == "org.ryoku.sddm.wallpaper"
path = actions[0].find("./annotate[@key='org.freedesktop.policykit.exec.path']")
assert path is not None and path.text == "/usr/local/libexec/ryoku-sddm-wallpaper"
print("PASS_STATIC: wallpaper-only Polkit action validated")
PY

stage="$ROOT/distro/scripts/ryoku-sddm"
helper="$ROOT/distro/scripts/ryoku-sddm-wallpaper"
cpp="$ROOT/distro/apps/ryoku-settings/src/WallpaperApplier.cpp"
qml="$ROOT/distro/apps/ryoku-settings/qml/pages/AppearancePage.qml"
grep -Fq 'abb3163c724935af888ba5ea9ac0c4f22afd8048' "$stage" &&
  pass "upstream pin fixed" || fail "upstream SDDM theme not pinned"
grep -Fq 'stage "$@"' "$stage" &&
  pass "theme staged independently" || fail "stage command missing"
grep -Fq 'read -r -p "Type SWITCH' "$stage" &&
  pass "DM switch requires explicit confirmation" || fail "DM switch confirmation missing"
grep -Fq 'previous-display-manager' "$stage" &&
  pass "GDM rollback information preserved" || fail "rollback info missing"
grep -Fq 'sddm-greeter-qt6 --test-mode' "$stage" &&
  pass "greeter preview before switch" || fail "greeter preview missing"
grep -Fq 'PKEXEC_UID' "$helper" &&
  pass "helper authenticates original user" || fail "PKEXEC_UID guard missing"
grep -Fq 'image/jpeg|image/png|image/webp' "$helper" &&
  pass "helper restricts real image MIME" || fail "wallpaper MIME guard missing"
grep -Fq 'wallpapers-private' "$helper" &&
  pass "helper supports local private gallery only" || fail "private gallery path missing"
! grep -Eq 'eval |bash -c|sh -c|systemctl|/etc/X11/default-display-manager' "$helper" &&
  pass "wallpaper helper has no DM/system command surface" || fail "helper contains privileged arbitrary command/DM switch"
grep -Fq 'syncLoginWallpaper(const QString &relativeId)' "$cpp" &&
  pass "Settings supports SDDM background update" || fail "missing Settings implementation"
grep -Fq 'proc->start(pkexec, {helper, relativeId})' "$cpp" &&
  pass "Settings sends basename-only argv to pkexec" || fail "unsafe or missing pkexec request"
grep -Fq 'onLoginWallpaperFinished' "$qml" &&
  pass "Appearance page reports login wallpaper failures" || fail "Settings fails silently"
grep -Fq 'previousLoginId !== draftLoginWallpaper' "$qml" &&
  pass "Settings syncs only login wallpaper changes" || fail "desktop wallpaper triggers root writes"

# Never publish private wallpaper binary/source or credentials as a side effect.
if grep -REn 'assets/wallpapers/1413|/home/paulo|ssh-rsa|BEGIN OPENSSH PRIVATE' "$ROOT/distro/sddm" >/dev/null 2>&1; then
  fail "SDDM public overlay contains private paths"
else
  pass "public SDDM overlay has no private paths"
fi

[[ "$failed" -eq 0 ]] || { echo "FAILURES=$failed" >&2; exit 1; }
echo "ALL PASS_STATIC (SDDM Debian port)"
