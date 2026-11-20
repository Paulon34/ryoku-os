# DMS Quattro bar → Wayland layer-shell surface

## Symptom (VM 201)

- `dms ipc call bar status id default` → `visible`
- `dms ipc call bar reveal id default` → `BAR_SHOW_SUCCESS`
- `dms ipc call bar getPosition id default` → `unknown`
- `niri msg layers`: Quickshell only on **Background**; **Top/Bottom/Overlay empty**

IPC “visible” is a **settings flag**, not proof a `PanelWindow` exists.

## Cause

`ShellCore.qml` (DMS 1.5.3) loads each bar with:

```qml
active: root.barSurfacesLoaded && (barConfig?.enabled ?? false) && …
```

If `barConfigs[].enabled` is missing, Quickshell coalesces to **false** → `DankBar` / `DankBarWindow` never instantiate → no `WlrLayershell` (`namespace: "dms:bar"`) on Top.

Ryoku’s earlier seed/merge set widgets + `visible`/`autoHide` but **omitted `enabled`**. On ryoku-desktop, DMS first-run writes full defaults (`enabled: true`) and merge only overlays style keys, keeping `enabled`. Our incomplete seed replaced that path.

`getPosition` maps `positions[barConfig.position]` with `positions = ["top","bottom","left","right"]`. Missing/`undefined` position → **`unknown`** (settings issue, not Niri).

## Fix

Declarative bar seed/merge must include at least:

| Key | Value | Why |
|-----|-------|-----|
| `enabled` | `true` | ShellCore Loader active |
| `position` | `0` (Top) | Enum + getPosition |
| `screenPreferences` | `["all"]` | Bind Virtual-1 / all outputs |
| `showOnLastDisplay` | `true` | Single-monitor fallback |
| `visible` | `true` | Show when window exists |
| `autoHide` | `false` | Stay revealed |

## Guest check (no session restart)

After HM switch (activation re-merges + `refreshSettings` when DMS is up):

```bash
jq '.barConfigs[]|select(.id=="default")|{id,enabled,position,visible,screenPreferences}' \
  ~/.config/DankMaterialShell/settings.json
dms ipc call bar getPosition id default   # expect: top
NIRI_SOCKET=$(find /run/user/$(id -u) -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)
NIRI_SOCKET="$NIRI_SOCKET" niri msg layers
# Expect a quickshell / dms:bar entry on Top (or Bottom), not only Background
```

If `enabled` flipped true but layers still empty, authorize a DMS restart / re-login so ShellCore recreates surfaces.
