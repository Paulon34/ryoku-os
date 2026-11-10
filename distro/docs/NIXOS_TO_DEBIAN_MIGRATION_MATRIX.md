# NixOS / ryoku-desktop → Debian Modular migration matrix

**Sources:** `Paulon34/ryoku-desktop` (public) + this repo’s `distro/`.  
**Not used:** private NixOS host trees / secrets (unauthorized).

Install legend: **APT** | **Nix/HM** | **Flatpak** | **N/A**

| App / concern | ryoku-desktop (NixOS/Hyprland) | Debian Modular method | Config port | Deps / notes | Compat | Gaps |
|---------------|--------------------------------|------------------------|-------------|--------------|--------|------|
| Compositor | Hyprland (HM) | **APT backports Hyprland** (default) + Nix Niri recovery | binds + GDM sessions | host Mesa / nixGL for Niri | Code ready | Guest Hyprland TBD |
| Shell | DMS 1.5.3 + patches | **Nix/HM** `dms-shell-ryoku` | settings merge | quickshell, jq | Patches reused | Visual Quattro guest TBD |
| Quickshell | via DMS | **Nix/HM** `pkgs.quickshell` | — | PATH wrapper | Required for ipc | SSH PATH was gap (fixed) |
| Matugen | HM templates → hypr colors | **Nix/HM** → `niri/colors.kdl` + DMS `niri/dms/colors.kdl` | templates | wallpaper dir | Seeded | Guest live palette TBD |
| Islands bar | DMS patches + styleBar | Same patches + `hosts/ryoku-islands` | HM merge | #26 enabled | Code ready | Guest screenshot TBD |
| Wallpapers | assets CC0 | **HM** file tree | same assets | — | OK | — |
| Kitty | HM + JetBrainsMono | **APT** pkg + **HM** config/font | kitty.nix | nerd-fonts Nix | OK | Fish shell optional |
| File manager | (varies) | **APT** Thunar | — | — | OK | — |
| Launcher | DMS / rofi | DMS spotlight + **APT/Nix** fuzzel fallback | scripts | — | OK | — |
| Notifications | DMS (+ historical mako) | **DMS only** | — | — | Ownership fixed | — |
| Network tray | NM applet | **APT** `network-manager-gnome` | Niri spawn | — | Wired | Needs APT apply once |
| Polkit GUI | polkit_gnome | **APT** `mate-polkit` | spawn wrapper | — | Wired | — |
| Clipboard | cliphist watchers | **Nix** cliphist + wl-paste | Niri spawn | wl-clipboard | Wired | — |
| PipeWire | NixOS services | **APT** + user systemd at login | — | — | OK | Dummy sink on VM expected |
| Portals | xdg-desktop-portal* | **APT** gtk+wlr | portals.conf | — | OK | — |
| GDM session | SDDM astronaut (GPL QML) | **GDM** + ryoku-niri.desktop | session wrapper | — | OK | Astronaut not ported |
| Ryoku Settings Qt | Nix app | **N/A** (later) | — | — | — | Not vendored |
| Video wallpaper | ryoku-video-wallpaper | **N/A** | — | — | — | Static only |
| dgop | optional monitor | **optional Nix** later | — | — | — | Does not hide bar |
| Flatpaks | settings.json list | Profile MVP later | — | flatpak | — | Design only |
| External .deb | rare | Profile metadata later | — | sha256 | — | No blobs in git |

## Preserve Nix/HM where it still makes sense

Keep **Nix pins** for: Niri, DMS+patches, Quickshell, Matugen, nixGL, fonts that APT lacks.  
Keep **APT** for: GDM, Mesa, PipeWire, NM, portals, Thunar, Kitty binary, polkit/nm agents.

## First migration actions (after desktop PASS)

1. Export allowlisted prefs from NixOS/desktop only with user consent  
2. Map packages through this matrix (no blind `nix-env` dump)  
3. Apply Debian Modular profile dry-run → HM switch  
4. Validate Quattro visually before expanding apps  
