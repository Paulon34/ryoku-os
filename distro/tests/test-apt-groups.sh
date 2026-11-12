#!/usr/bin/env bash
# Validate APT group files and bootstrap union for minimal/full.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fail=0

pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

for f in packages-base.txt packages-hyprland.txt packages-full.txt; do
  [[ -f "$ROOT/distro/apt/$f" ]] && pass "$f" || fail_msg "missing $f"
done

need_base=(firefox-esr kitty thunar thunar-archive-plugin file-roller imv flatpak grim slurp fonts-noto-core papirus-icon-theme)
for pkg in "${need_base[@]}"; do
  grep -Eq "^${pkg}$" "$ROOT/distro/apt/packages-base.txt" \
    && pass "base has $pkg" \
    || fail_msg "packages-base missing $pkg"
done

need_full=(mpv vlc gimp libreoffice-gtk3 blueman pavucontrol cliphist)
for pkg in "${need_full[@]}"; do
  grep -Eq "^${pkg}$" "$ROOT/distro/apt/packages-full.txt" \
    && pass "full has $pkg" \
    || fail_msg "packages-full missing $pkg"
done

# No duplicates between base and full (review hygiene; bootstrap also dedupes)
while read -r pkg; do
  [[ -z "$pkg" ]] && continue
  if grep -Eq "^${pkg}$" "$ROOT/distro/apt/packages-base.txt"; then
    fail_msg "packages-full duplicates base entry: $pkg"
  fi
done < <(grep -vE '^\s*(#|$)' "$ROOT/distro/apt/packages-full.txt")
pass "full list has no base duplicates"

grep -Eq '^hyprland$' "$ROOT/distro/apt/packages-hyprland.txt" || fail_msg "hyprland list"
grep -Eq '^hyprland-guiutils$' "$ROOT/distro/apt/packages-hyprland.txt" || fail_msg "hyprland-guiutils"

# Bootstrap dry-run still works with full profile (plan only)
set +e
out=$("$ROOT/distro/scripts/ryoku-bootstrap" --dry-run --user runner --profile full --yes 2>&1)
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  pass "bootstrap dry-run --profile full"
else
  fail_msg "bootstrap dry-run full failed: $rc"
  echo "$out" | tail -30 >&2
fi
echo "$out" | grep -Eq 'profile:[[:space:]]+full' || fail_msg "dry-run should report profile full"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (apt-groups)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
