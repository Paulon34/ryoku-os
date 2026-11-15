#!/usr/bin/env bash
# Structural + sequential apply validation for all Ryoku DMS 1.5.3 patches.
# PASS_STATIC only — clones pinned DankMaterialShell v1.5.3; never invents PASS_REAL.
#
# Fails on: malformed hunks (count/orphan), reject, fuzz>0.
# Logs each patch name. Does not replace existing shallow greps elsewhere.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PATCH_DIR="$ROOT/distro/flake/patches/dms/1.5.3"
NIX_PKG="$ROOT/distro/flake/pkgs/dms-shell-ryoku.nix"
# Tag + commit must match flake input github:AvengeMedia/DankMaterialShell/v1.5.3
DMS_TAG="${RYOKU_DMS_TAG:-v1.5.3}"
DMS_COMMIT="${RYOKU_DMS_COMMIT:-069ddab041c738236a8910e4c39b65d9628d3018}"

fail=0
pass() { echo "PASS_STATIC: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

# Exact apply order from dms-shell-ryoku.nix (must stay in sync).
mapfile -t PATCH_LIST < <(awk '
  /for p in \\/ {inlist=1; next}
  inlist && /do/ {exit}
  inlist {
    gsub(/^[ \t]+/, "");
    gsub(/[ \\]+$/, "");
    if ($0 != "") print
  }
' "$NIX_PKG")

if [[ "${#PATCH_LIST[@]}" -lt 20 ]]; then
  fail_msg "could not parse patch list from dms-shell-ryoku.nix (got ${#PATCH_LIST[@]})"
  exit 1
fi

# --- Structural hunk validation (bare newline = context blank, GNU-compatible) ---
# Hard-fail: premature headers / orphan body / unreadable lines (the cava class of
# bugs). Soft count mismatches that GNU patch still applies are noted but not fatal
# here — sequential fuzz=0 apply below is the authoritative gate.
struct_out=$(python3 - "$PATCH_DIR" "${PATCH_LIST[@]}" <<'PY'
import re, sys
from pathlib import Path

patch_dir = Path(sys.argv[1])
names = sys.argv[2:]
errors = []
soft = []

def validate(path: Path):
    local_hard, local_soft = [], []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines(True)
    i = 0
    hunk_n = 0
    while i < len(lines):
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", lines[i])
        if not m:
            i += 1
            continue
        hunk_n += 1
        old_n = int(m.group(2) or "1")
        new_n = int(m.group(4) or "1")
        i += 1
        old_c = new_c = 0
        while i < len(lines) and (old_c < old_n or new_c < new_n):
            l = lines[i]
            if l.startswith("\\"):
                i += 1
                continue
            if l == "\n":
                kind = " "
            elif l.startswith((" ", "+", "-")):
                kind = l[0]
            elif l.startswith(("@@ ", "diff ", "--- ", "+++ ")):
                local_hard.append(
                    f"{path.name} hunk#{hunk_n}: premature header at line {i+1} "
                    f"(got -{old_c}/+{new_c} need -{old_n}/+{new_n})"
                )
                break
            else:
                local_hard.append(f"{path.name} hunk#{hunk_n}: bad line {i+1}: {l!r}")
                i += 1
                continue
            if kind in (" ", "-"):
                old_c += 1
            if kind in (" ", "+"):
                new_c += 1
            i += 1
        else:
            if old_c != old_n or new_c != new_n:
                local_soft.append(
                    f"{path.name} hunk#{hunk_n}: declared -{old_n}/+{new_n} got -{old_c}/+{new_c}"
                )
            if i < len(lines):
                nxt = lines[i]
                if nxt == "\n" or (
                    nxt.startswith((" ", "+", "-"))
                    and not nxt.startswith("---")
                    and not nxt.startswith("+++")
                ):
                    local_hard.append(
                        f"{path.name} hunk#{hunk_n}: orphan body line {i+1}: {nxt!r}"
                    )
        continue
    return local_hard, local_soft

for name in names:
    p = patch_dir / name
    if not p.is_file():
        errors.append(f"missing patch file: {name}")
        continue
    h, s = validate(p)
    errors.extend(h)
    soft.extend(s)

for s in soft:
    print(f"NOTE: soft count drift (GNU patch may still apply): {s}", file=sys.stderr)
if errors:
    for e in errors:
        print(e)
    sys.exit(1)
print(f"structural_ok count={len(names)} soft_notes={len(soft)}")
PY
) || {
  echo "$struct_out" >&2
  fail_msg "structural hunk validation failed (malformed/orphan)"
  exit 1
}
pass "$struct_out"

# --- Sequential apply against pinned upstream (fuzz=0, no rejects) ---
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
src="$work/dms"
echo "Cloning DankMaterialShell ${DMS_TAG} (${DMS_COMMIT})..."
git clone --quiet --depth 1 --branch "$DMS_TAG" \
  https://github.com/AvengeMedia/DankMaterialShell.git "$src"
got=$(git -C "$src" rev-parse HEAD)
if [[ "$got" != "$DMS_COMMIT" ]]; then
  fail_msg "DMS pin mismatch: expected $DMS_COMMIT got $got"
  exit 1
fi
pass "DMS pin $DMS_TAG @ ${DMS_COMMIT:0:12}"

tree="$work/tree"
cp -a "$src/quickshell" "$tree"
cd "$tree"

for p in "${PATCH_LIST[@]}"; do
  echo "APPLY: $p"
  # Capture patch stdout/stderr; reject fuzz and rejects.
  if ! out=$(patch -p1 --fuzz=0 --forward --batch < "$PATCH_DIR/$p" 2>&1); then
    echo "$out" >&2
    fail_msg "patch apply failed: $p"
    exit 1
  fi
  if grep -Eqi 'fuzz|reject|FAILED|malformed' <<<"$out"; then
    echo "$out" >&2
    fail_msg "patch reported fuzz/reject/malformed: $p"
    exit 1
  fi
  pass "applied $p (fuzz=0)"
done

# API / QML contract smoke (post-apply tree) — still PASS_STATIC.
for f in \
  Services/CavaService.qml \
  Modules/DankBar/Widgets/AudioVisualization.qml \
  Modules/DankBar/Widgets/MediaIsland.qml \
  Modules/DankBar/Popouts/MediaIslandPopout.qml \
  Modules/DankDash/MediaPlayerTab.qml
do
  [[ -f "$tree/$f" ]] && pass "post-apply has $f" || fail_msg "missing $f"
done

grep -Fq 'property int refCount' "$tree/Services/CavaService.qml" \
  && pass "CavaService.refCount present" || fail_msg "CavaService.refCount missing"
grep -Fq 'running: root.cavaAvailable && root.refCount > 0' "$tree/Services/CavaService.qml" \
  && pass "CavaService suspends when refCount=0" || fail_msg "cava process gate wrong"
grep -Fq 'service: CavaService' "$tree/Modules/DankBar/Widgets/AudioVisualization.qml" \
  && pass "AudioVisualization uses Ref→CavaService" || fail_msg "AudioVisualization Ref missing"
grep -Fq 'active: root.live' "$tree/Modules/DankBar/Widgets/AudioVisualization.qml" \
  && pass "AudioVisualization Loader gated on live" || fail_msg "live gate missing"
grep -Fq 'audioVisualizerEnabled' "$tree/Common/SettingsData.qml" \
  && pass "SettingsData.audioVisualizerEnabled" || fail_msg "audioVisualizerEnabled missing"

for f in \
  Modules/DankBar/Widgets/MediaIsland.qml \
  Modules/DankBar/Popouts/MediaIslandPopout.qml \
  Modules/DankDash/MediaPlayerTab.qml
do
  grep -Fq 'AudioVisualization' "$tree/$f" \
    && pass "$f wires AudioVisualization" || fail_msg "$f missing AudioVisualization"
  grep -Fq 'CavaService.cavaAvailable' "$tree/$f" \
    && pass "$f gates on cavaAvailable" || fail_msg "$f missing cavaAvailable gate"
  grep -Fq 'audioVisualizerEnabled' "$tree/$f" \
    && pass "$f respects audioVisualizerEnabled" || fail_msg "$f missing visualizer setting"
  ! grep -Fq 'Math.random' "$tree/$f" \
    && pass "$f has no fake spectrum" || fail_msg "$f invents Math.random spectrum"
done

grep -Fq 'MprisPlaybackState.Playing' "$tree/Modules/DankDash/MediaPlayerTab.qml" \
  && pass "expanded player gates on MprisPlaying" || fail_msg "MediaPlayerTab MPRIS gate missing"
grep -Fq 'import qs.Modules.DankBar.Widgets' "$tree/Modules/DankBar/Popouts/MediaIslandPopout.qml" \
  && pass "popout imports DankBar.Widgets for AudioVisualization" || fail_msg "popout import missing"
grep -Fq 'import qs.Modules.DankBar.Widgets' "$tree/Modules/DankDash/MediaPlayerTab.qml" \
  && pass "MediaPlayerTab imports DankBar.Widgets" || fail_msg "MediaPlayerTab import missing"

# Quattro + Islands share the same patched tree (style substituted at build time).
grep -Fq 'ryokuShellStyle' "$NIX_PKG" \
  && pass "shell style injected into shared DMS tree" || fail_msg "style injection missing"

if [[ "$fail" -eq 0 ]]; then
  echo "ALL PASS_STATIC (dms-patches)"
  exit 0
fi
echo "FAILURES=$fail" >&2
exit 1
