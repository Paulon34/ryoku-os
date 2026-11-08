# Hyprland → Niri keybind matrix

Source: [Paulon34/ryoku-desktop](https://github.com/Paulon34/ryoku-desktop) `home/hyprland.nix` + `home/dms.nix`.

Niri config: `distro/flake/home/niri.nix` (ENTREGA A/B).

| Action | Hyprland (ryoku-desktop) | Niri (Ryoku Debian) | Status |
|--------|--------------------------|---------------------|--------|
| Terminal | `$mod, RETURN` → kitty | `Mod+Return` → kitty | Parity |
| Launcher | `$mod, SPACE` → DMS/rofi | `Mod+Space` → `ryoku-launcher` (DMS spotlight → fuzzel) | B |
| File manager | `$mod, E` | `Mod+E` → thunar | Parity |
| Close window | `$mod, Q` | `Mod+Q` | Parity |
| Fullscreen | `$mod, F` | `Mod+F` maximize; `Mod+Shift+F` fullscreen | Mapped |
| Toggle float | `$mod, V` | — | Niri columns; N/A |
| Pseudo | `$mod, P` | — | Hyprland-only |
| Notepad (DMS) | (DMS) | `Mod+Comma` settings; notepad via DMS UI | Partial |
| Exit compositor | `$mod SHIFT, E` | `Mod+Shift+E` quit | Parity |
| Focus L/R/U/D | arrows + HJKL | arrows + HJKL | Parity |
| Move window | `$mod SHIFT` + HJKL | `Mod+Shift` + HJKL | Parity |
| Workspace 1–10 | `$mod, 0-9` | `Mod+0-9` | Parity |
| Move to workspace | `$mod SHIFT, 0-9` | `Mod+Shift+0-9` | Parity |
| Mouse workspace | mouse_down/up | — | Optional later |
| Wallpaper | `$mod, W` | `Mod+W` → change-wallpaper + Matugen | B |
| Screenshot region | Print → grim\|swappy | `Print` → ryoku-screenshot region | B (no swappy) |
| Screenshot full | `$mod, Print` | `Mod+Print` → full | B |
| Clipboard hist | `$mod, C` cliphist\|rofi | `Mod+C` → ryoku-clipboard | B |
| Notifications | (DMS) | `Mod+N` → `ryoku-dms-ipc` notifications | B |
| Power menu | (DMS) | `Mod+X` → `ryoku-dms-ipc` powermenu | B |
| Lock | `$mod, X` hyprlock / `$mod, L` dms lock | `Mod+Shift+X` → `ryoku-dms-ipc` lock | B |
| Volume | XF86Audio* → wpctl | XF86Audio* → wpctl | Parity |
| Brightness | XF86MonBrightness* | XF86MonBrightness* → brightnessctl | B |

## Shell styles

| Style | Hyprland/DMS (ryoku-desktop) | Niri/DMS (Debian) |
|-------|------------------------------|-------------------|
| Quattro (default) | Flat bar, radius 8, Omarchy-inspired | Same via patched DMS 1.5.3 + `ryoku.profile.shellStyle` |
| Islands | Floating capsules | Same |
| Quattro workspace QML | Custom `Hyprland.*` strip | Stock DMS switcher on Niri (`CompositorService.isHyprland` gate) |
| Matugen compositor colors | `hyprland-colors.conf` | `~/.config/niri/colors.kdl` |

Set via host profile: `shellStyle = "quattro" | "islands";` in `distro/flake/hosts/<user>/default.nix`.
