# Session service ownership (GDM → Niri)

Clear owners avoid duplicate trays, notification daemons, and polkit agents.

| Concern | Owner | How | Do not |
|---------|-------|-----|--------|
| Compositor | Niri | `ryoku-niri-session` → `niri --session` | Second compositor |
| Shell / notifications / OSD | DMS Quattro | `spawn-at-startup ryoku-start-dms` | mako / dunst / swaync |
| NM tray | Niri spawn | `ryoku-nm-applet` → `nm-applet` | systemd user nm-applet + Niri both |
| Polkit GUI prompts | Niri spawn | `ryoku-polkit-agent` (mate-polkit) | Skip agent and wonder why pkexec hangs |
| Clipboard history DB | Niri spawn | `wl-paste --watch cliphist store` | Expect cliphist UI with empty DB |
| Clipboard UI (primary) | DMS | `ryoku-dms-ipc clipboard` | Fight DMS with a second clipboard UI |
| PipeWire | systemd --user | enabled at login by Debian user session | `systemctl --user enable` during headless SSH bootstrap |
| NetworkManager | system systemd | bootstrap `enable --now` | Duplicate NM instances |
| Portals | xdg-desktop-portal{,-gtk,-wlr} | APT + `portals.conf` | Random extra portal backends without need |

## Autostart rules

- Prefer **Niri `spawn-at-startup`** for desktop agents that need `WAYLAND_DISPLAY`.
- Prefer **systemd --user** only for oneshots that merge files (e.g. `ryoku-dms-bar.service`).
- Never enable a long-running `ryoku-dms.service` alongside Niri spawn (double shell).
- Wrappers must **exit 0** if optional APT binaries are missing (session must still start).
