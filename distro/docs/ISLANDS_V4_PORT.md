# Islands V4 → Debian Niri (reuse, don’t reinvent)

Sources: `Paulon34/ryoku-desktop` (public). Private `ryoku-nixos` was **not**
reachable from this agent — re-diff when Paulo provides a read-only clone.

## What was already reused

- All 23 DMS 1.5.3 Ryoku patches (byte-identical to desktop), including
  `ryoku-bar-islands`, media/central island, control-center, launcher, OSD.
- Islands `styleBar` / `styleSettings` from desktop `home/dms.nix`.
- `#26` surface guards: `enabled=true`, `position=0`, `screenPreferences=["all"]`.

## What this port adds

| Piece | Change |
|-------|--------|
| Niri Material You | `include optional=true "dms/colors.kdl"` (DMS matugen output) after fallback `colors.kdl` |
| Wallpaper | `change-wallpaper` is **DMS-first** (desktop parity); then user matugen + `niri msg action load-config-file` |
| Gaps | Islands `gaps 10` (Hypr `gaps_out`); Quattro `gaps 8` |
| Test host | `hosts/ryoku-islands` with `shellStyle = "islands"` |

## Not ported (honest)

- Hyprland blur / window shadow / inactive opacity / animation curves → Niri N/A
- Video wallpaper, SDDM astronaut, Ryoku Settings Qt, KDE DankMatugen
- Private V4-only tweaks from inaccessible `ryoku-nixos`

## Apply Islands on the guest (no agent restart)

```bash
cd ~/ryoku-os-visual && git fetch origin && git checkout --detach origin/cursor/debian-islands-v4-port-8dbd
sudo ./distro/scripts/ryoku-bootstrap --apply --user paulo --skip-apt --skip-nix \
  --profile minimal --visual balanced --shell-style islands
home-manager switch --flake "$PWD/distro/flake#paulo"

jq -r '.appearance.shellStyle' ~/.config/ryoku/settings.json
jq '.barConfigs[]|select(.id=="default")|{enabled,noBackground,widgetTransparency,leftWidgets}' \
  ~/.config/DankMaterialShell/settings.json

NIRI_SOCKET=$(find /run/user/$(id -u) -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)
NIRI_SOCKET="$NIRI_SOCKET" niri msg layers
test -f ~/.config/niri/dms/colors.kdl && head -n 15 ~/.config/niri/dms/colors.kdl
~/.local/bin/change-wallpaper
grim ~/Pictures/Screenshots/islands-$(date +%Y%m%d-%H%M%S).png
```

`GUEST_NOT_RUN` until layers Top + screenshot are confirmed. Do not invent `PASS_MANUAL`.
