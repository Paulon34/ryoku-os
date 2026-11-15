# Session service ownership (GDM → Hyprland primary / Niri recovery)

Clear owners avoid duplicate trays, notification daemons, and polkit agents.

| Concern | Owner | How | Do not |
|---------|-------|-----|--------|
| Compositor | Hyprland (primary) / Niri (recovery) | `ryoku-*-session` wrappers | Second compositor |
| Shell / notifications / OSD / MPRIS island | DMS Quattro | `exec-once` / `spawn-at-startup ryoku-start-dms` | mako / dunst / swaync / stock Media.qml |
| Bar CPU/RAM/temp | DMS native `cpuUsage` / `memUsage` / `cpuTemp` (DgopService) | Quattro `rightWidgets` + `~/.local/bin/dgop` | Fake percentages or continuous `nvidia-smi` |
| Bar GPU / VRAM | **Not claimed** until DgopService exposes honest GPU IDs on this DMS pin | `ryoku-hardware --sensors` one-shot | Blind dgop→dux-gop swap; waking hybrid NVIDIA for wallpaper/metrics |
| Video wallpaper | `ryoku-video-wallpaper` + mpvpaper user unit | Settings Appearance → Video; VA-API iGPU | Second wallpaper daemon (hyprpaper/swww); `hwdec=auto` (wakes dGPU) |
| Video smart pause/unload | `ryoku-video-wallpaper-smart` (`watch`) | Hyprland socket2 / poll; unload → DMS poster | Rematugen on every resume; duplicate mpvpaper |
| Media Island CAVA | DMS `CavaService` (refCount) + APT `cava` | Media Island / Mini Player when Playing | Second cava process; fake spectrum when cava missing |
| Power tips | `ryoku-power-policy` timer | Battery → economy wallpaper + optional ppd | Continuous nvidia-smi; inventing GPU % |
| NM tray | compositor spawn | `ryoku-nm-applet` → `nm-applet` | systemd user nm-applet + spawn both |
| Polkit GUI prompts | compositor spawn | `ryoku-polkit-agent` (mate-polkit; skips if agent already alive) | Two agents (xdg autostart + exec-once) |
| Clipboard history DB | compositor spawn | `wl-paste --watch cliphist store` | Expect cliphist UI with empty DB |
| Clipboard UI (primary) | DMS | `ryoku-dms-ipc clipboard` | Fight DMS with a second clipboard UI |
| PipeWire | systemd --user | enabled at login by Debian user session | `systemctl --user enable` during headless SSH bootstrap |
| NetworkManager | system systemd | bootstrap `enable --now` | Duplicate NM instances |
| Portals | xdg-desktop-portal{,-gtk,-wlr,hyprland} | APT + `portals.conf` | Random extra portal backends without need |

## Autostart rules

- Prefer **Hyprland `exec-once` / Niri `spawn-at-startup`** for desktop agents that need `WAYLAND_DISPLAY`.
- Prefer **systemd --user** only for oneshots that merge files (e.g. `ryoku-dms-bar.service`).
- Never enable a long-running `ryoku-dms.service` alongside compositor spawn (double shell).
- Wrappers must **exit 0** if optional APT binaries are missing (session must still start).

## Performance audit notes (code-only)

- Duplicate polkit agents: mitigated by `ryoku-polkit-agent` skip-if-alive; still disable
  conflicting `*.desktop` Autostart entries for gnome-polkit if both fire on a host.
- Redundant DMS path units (`ryoku-dms-bar` / `ryoku-dms-session`) are oneshots and
  idempotent; they are not a second shell.
- Do not add a second screenshot stack (grim/slurp/swappy is the only Ryoku path).

## Secondary warning triage (Hyprland primary)

| Symptom | Likely class | Action |
|---------|--------------|--------|
| `niri msg` / Niri socket errors while on Hyprland | Harmless (recovery compositor still installed) | Ignore unless intentionally in Niri session |
| Duplicate polkit agent logs | Real if two agents prompt | Keep skip-if-alive; disable extra Autostart |
| Tray / StatusNotifier D-Bus name taken | Often harmless race at login | One NM applet owner only (`ryoku-nm-applet`) |
| Power profiles daemon missing | Harmless on desktops without it | Optional APT later; do not block session |
| Thunar thumbnailer warnings | Harmless unless previews broken | Install `tumbler` only if user wants thumbs |
| a11y / AT-SPI registration noise | Do **not** disable | Keep accessibility bus intact |
| Portal Settings backend registration | Real if apps stay light | `org.freedesktop.impl.portal.Settings=gtk` + session `GTK_THEME` |
