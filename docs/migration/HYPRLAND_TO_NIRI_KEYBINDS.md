# Hyprland → Niri keybind matrix

Source of truth for Ryoku Desktop Hyprland binds: [Paulon34/ryoku-desktop](https://github.com/Paulon34/ryoku-desktop) `home/hyprland.nix`.

Niri foundation config: `distro/flake/home/niri.nix` (ENTREGA A).

| Action | Hyprland (ryoku-desktop) | Niri (Ryoku Debian A) | Notes |
|--------|--------------------------|------------------------|-------|
| Terminal | `$mod, RETURN` → kitty | `Mod+Return` → kitty | Parity |
| Launcher | `$mod, SPACE` → DMS/rofi menu | `Mod+Space` → fuzzel | DMS launcher = ENTREGA B |
| File manager | `$mod, E` → fileManager | `Mod+E` → thunar | Parity |
| Close window | `$mod, Q` killactive | `Mod+Q` close-window | Parity |
| Fullscreen | `$mod, F` fullscreen | `Mod+F` maximize-column; `Mod+Shift+F` fullscreen-window | Niri distinguishes maximize vs fullscreen |
| Toggle float | `$mod, V` togglefloating | — | Niri is tiling/columns; float TBD B |
| Pseudo | `$mod, P` pseudo | — | Hyprland-only |
| Exit compositor | `$mod SHIFT, E` exit | `Mod+Shift+E` quit | Parity |
| Focus L/R/U/D | arrows + HJKL | arrows + HJKL (column/window) | Mapped to columns/windows |
| Move window | `$mod SHIFT` + HJKL | `Mod+Shift` + HJKL | Column/window move |
| Workspace 1–10 | `$mod, 0-9` | `Mod+0-9` | Parity |
| Move to workspace | `$mod SHIFT, 0-9` | `Mod+Shift+0-9` | Parity |
| Mouse workspace | mouse_down/up | — | Optional B |
| Wallpaper | `$mod, W` change-wallpaper | — | Matugen/wallpaper = B |
| Screenshot region | Print → grim\|swappy | — | Optional B (grim/slurp packaged) |
| Screenshot full | `$mod, Print` | — | Optional B |
| Clipboard hist | `$mod, C` cliphist\|rofi | — | Optional B |
| Lock | `$mod, X` hyprlock / `$mod, L` dms lock | — | DMS lock = B |
| Volume | XF86Audio* → wpctl | XF86Audio* → wpctl | Parity |
| Brightness | XF86MonBrightness* | — | Optional laptop profile C |

## ENTREGA B follow-ups

- Port DankMaterialShell (Quattro/Islands) onto Niri
- Restore lock, wallpaper, clipboard, screenshot binds
- Document any Niri-only scroll/column gestures that replace Hyprland mouse workspace binds
