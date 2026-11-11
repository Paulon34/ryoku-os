#!/usr/bin/env bash
# Static + parser guard: Hyprland conf must match Debian APT ~0.55.2 semantics.
# Parser models Hyprland v0.55.2 ConfigManager::handleWindowrule / handleLayerrule:
# CVarList2 comma-split, each field requires "key value" (space), match:* or effect.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HYPR="$ROOT/distro/flake/home/hyprland.nix"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$HYPR" ]] || fail "hyprland.nix missing"

# Ban known-bad forms in emitted conf lines (ignore # comments).
code_lines() { grep -vE '^\s*#' "$HYPR" || true; }

code_lines | grep -Fq 'windowrulev2' &&
  fail "windowrulev2 is deprecated on Hyprland 0.55.2"
code_lines | grep -Fq 'new_optimizations' &&
  fail "blur:new_optimizations removed/unsafe for 0.55.2 target — omit it"
# Bare effects (no value) → "invalid field float: missing a value"
code_lines | grep -Eq 'windowrule[[:space:]]*=[[:space:]]*(float|center)[[:space:]]*,' &&
  fail "bare windowrule effects invalid in 0.55.2 — use 'float on' / 'center on'"
code_lines | grep -Eq 'windowrule[[:space:]]*=.*[^:](class|title):' &&
  fail "legacy class:/title: matchers invalid — use match:class / match:title"
code_lines | grep -Eq 'layerrule[[:space:]]*=[[:space:]]*(noanim|blur)[[:space:]]*,' &&
  fail "bare layerrule effects invalid — use 'no_anim on' / 'blur on' + match:namespace"

code_lines | grep -Eq 'windowrule[[:space:]]*=[[:space:]]*match:class .*float on' ||
  fail "expected windowrule = match:class ..., float on for 0.55.2"
code_lines | grep -Eq 'windowrule[[:space:]]*=[[:space:]]*match:title .*float on' ||
  fail "expected windowrule = match:title ..., float on for 0.55.2"
# Quattro layerrules must use 0.55.2 keyword form when present.
if code_lines | grep -Eq 'layerrule[[:space:]]*='; then
  code_lines | grep -Eq 'layerrule[[:space:]]*=.*match:namespace' ||
    fail "layerrule must use match:namespace on 0.55.2"
  code_lines | grep -Eq 'layerrule[[:space:]]*=.*(no_anim on|blur on|ignore_alpha )' ||
    fail "layerrule effects need values (no_anim on / blur on / ignore_alpha N)"
fi

grep -Fq '0.55' "$HYPR" ||
  fail "hyprland.nix must document Debian ~0.55.x target"
grep -Fq 'ryoku-start-dms' "$HYPR" ||
  fail "Hyprland must exec-once DMS"
! grep -Fq 'exec-once = niri' "$HYPR" ||
  fail "Hyprland must not start Niri"
! grep -Fq 'spawn-at-startup' "$HYPR" ||
  fail "Hyprland must not use Niri spawn-at-startup"

# Mini parser: extract rule RHS from Nix '' strings and validate fields.
python3 - "$HYPR" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
blocks = re.findall(r"(?:conf|quattroLayerRules|islandsLayerRules) = ''(.*?)'';", text, re.S)
if not blocks:
    sys.exit("FAIL: conf/layerrule ''…'' blocks not found in hyprland.nix")
body = "\n".join(blocks)

WINDOW_EFFECTS = {
    "float", "center", "size", "pin", "fullscreen", "maximize", "workspace",
    "opacity", "rounding", "idleinhibit", "suppressevent", "no_anim",
}
LAYER_EFFECTS = {
    "no_anim", "blur", "blur_popups", "ignore_alpha", "dim_around", "xray",
    "animation", "order", "above_lock", "no_screen_share",
}
BANNED_ALIASES = {"noanim", "ignorealpha", "ignorezero"}

def fields(rhs: str):
    # Model CVarList2 default: split on unescaped commas.
    parts, buf, i = [], [], 0
    while i < len(rhs):
        c = rhs[i]
        if c == "," and (i == 0 or rhs[i - 1] != "\\"):
            part = "".join(buf).strip()
            if part:
                parts.append(part)
            buf = []
        else:
            buf.append(c)
        i += 1
    part = "".join(buf).strip()
    if part:
        parts.append(part)
    return parts

errors = []
for kind, effects in (("windowrule", WINDOW_EFFECTS), ("layerrule", LAYER_EFFECTS)):
    for line in body.splitlines():
        s = line.strip()
        if s.startswith("#") or not s.startswith(f"{kind} ="):
            continue
        rhs = s.split("=", 1)[1].strip()
        if not rhs:
            errors.append(f"{kind}: empty RHS: {s}")
            continue
        for el in fields(rhs):
            if " " not in el:
                errors.append(f"{kind}: missing value (0.55.2): {el!r} in {s}")
                continue
            key, _, val = el.partition(" ")
            val = val.strip()
            if not val:
                errors.append(f"{kind}: empty value for {key!r} in {s}")
                continue
            if key.startswith("match:"):
                if not key[len("match:"):]:
                    errors.append(f"{kind}: empty match prop in {s}")
                continue
            if key in BANNED_ALIASES:
                errors.append(f"{kind}: banned alias {key!r} (use 0.55.2 name) in {s}")
                continue
            if key in {"class", "title", "namespace"}:
                errors.append(f"{kind}: use match:{key} not bare {key} in {s}")

if errors:
    print("FAIL: 0.55.2 rule parser:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)
print("PASS: windowrule/layerrule fields parse as 0.55.2 key+value")
PY

# Niri recovery must remain packaged even when hyprland is primary.
NIRI="$ROOT/distro/flake/home/niri.nix"
grep -Fq 'niri' "$NIRI" || fail "niri.nix missing niri package"
! grep -Fq 'mkIf enabled' "$NIRI" ||
  fail "niri.nix must not gate the whole module on compositor==niri (recovery)"
grep -Fq 'xdg.configFile."niri/config.kdl"' "$NIRI" ||
  fail "niri config.kdl must always be written for GDM recovery"

# Keep GDM/Hyprland environment compliant with 0.53+ startup advice.
SESSION="$ROOT/distro/session/ryoku-hyprland-session"
DESKTOP="$ROOT/distro/session/ryoku-hyprland.desktop"
APT="$ROOT/distro/apt/packages-hyprland.txt"
grep -Fq 'exec /usr/bin/start-hyprland' "$SESSION" ||
  fail "Ryoku GDM wrapper should prefer start-hyprland"
grep -Fq 'export XDG_CURRENT_DESKTOP="Hyprland"' "$SESSION" ||
  fail "GDM wrapper must not set XDG_CURRENT_DESKTOP=Hyprland:Ryoku"
! grep -Fq 'Hyprland:Ryoku' "$SESSION" "$HYPR" ||
  fail "XDG_CURRENT_DESKTOP must be Hyprland (not Hyprland:Ryoku)"
grep -Fxq 'Name=Ryoku (Hyprland)' "$DESKTOP" ||
  fail "GDM session display name must stay Ryoku (Hyprland)"
grep -Fxq 'DesktopNames=Hyprland' "$DESKTOP" ||
  fail "GDM session should advertise canonical Hyprland desktop identifier"
grep -Fxq 'hyprland-guiutils' "$APT" ||
  fail "Debian backports GUI recovery helpers missing"
grep -Fq 'XDG_CURRENT_DESKTOP = "Hyprland";' "$HYPR" ||
  fail "Home Manager should export the canonical Hyprland desktop identifier"
grep -Fq 'lib.mkMerge' "$HYPR" ||
  fail "hyprland.nix must keep lib.mkMerge (HM config key)"

# Bootstrap must accept verified 0.55.2 forms (not treat them as 0.56-only).
BOOT="$ROOT/distro/scripts/ryoku-bootstrap"
if grep -Fq "grep -Fq 'no_anim on, match:namespace'" "$BOOT"; then
  fail "bootstrap still rejects verified 0.55.2 layerrule form as 0.56-only"
fi
if grep -Fq "grep -Eq 'windowrule = float on,'" "$BOOT"; then
  fail "bootstrap still rejects verified 0.55.2 windowrule 'float on' as 0.56-only"
fi
grep -Fq '0.55.2 syntax guard' "$BOOT" ||
  fail "bootstrap should keep a 0.55.2 syntax guard"

pass "Hyprland conf targets Debian 0.55.2; Niri recovery always available"
