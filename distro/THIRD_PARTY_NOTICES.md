# Third-party notices — Ryoku Debian (`distro/`)

First-party Ryoku OS / Zaquion licensing remains per-component — see `/LICENSING.md` and `docs/licensing/strategy.md`.

This tree adds Debian + Nix desktop glue. It **does not vendor** Hyprland DMS patches from ryoku-desktop in ENTREGA A (those arrive with ENTREGA B and keep their upstream licenses).

## Referenced projects (not redistributed as source here)

| Component | Role | License (upstream / nixpkgs metadata) |
|-----------|------|----------------------------------------|
| Debian 13 Trixie | Base userland | DFSG; per-package |
| Nix (`nix-bin`, `nix-setup-systemd`) | Multi-user store + systemd units | LGPL-2.1+ (Nix) |
| nixpkgs | Package set / Niri build | MIT (nixpkgs) |
| Home Manager | Standalone user config | MIT |
| Niri | Wayland compositor | GPL-3.0-or-later |
| nixGL | GL/Vulkan wrappers on non-NixOS | MIT |
| Kitty | Terminal (APT and/or Nix) | GPL-3.0-only |
| Thunar | File manager (APT) | GPL-2.0-or-later |
| Fuzzel | Launcher (APT/Nix) | MIT |
| GDM | Display manager (APT) | GPL-2.0-or-later |
| SDDM + SDDM Astronaut | Optional Debian Qt6 greeter and theme, upstream pinned | GPL-2.0-or-later / GPL-3.0-or-later |
| PipeWire / WirePlumber | Audio (APT) | MIT / LGPL |
| NetworkManager | Networking (APT) | GPL-2.0-or-later |
| xdg-desktop-portal (+ gtk/wlr) | Portals (APT) | LGPL-2.1+ |
| polkit | Privilege broker (APT) | LGPL-2.0+ |
| Mesa / XWayland | Graphics (APT) | MIT / X11-style |
| xwayland-satellite | XWayland helper (Nix) | MPL-2.0 |

## Included from ryoku-desktop / DMS (ENTREGA B)

| Path | Origin | Licence |
|------|--------|---------|
| `distro/flake/patches/dms/1.5.3/*.patch` | Ryoku patches on DankMaterialShell 1.5.3 | MIT — `distro/LICENSES/MIT-DankMaterialShell.txt` (+ Ryoku MIT) |
| `distro/assets/wallpapers/ryoku-*.jpg` | ryoku-desktop public wallpapers | CC0-1.0 (`distro/assets/wallpapers/LICENSE`) |
| Behaviour reference Omarchy Quattro | No code copied | MIT — `distro/LICENSES/MIT-Omarchy.txt` |

## Visual / UX reference

[Paulon34/ryoku-desktop](https://github.com/Paulon34/ryoku-desktop) · [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) `v1.5.3` (flake input).

SDDM Astronaut QML is now an **optional Debian port**, staged after an explicit
administrator action. Only the three GPL-3.0-or-later Ryoku visual overlay
files are vendored under `distro/sddm/astronaut-overlay/`; they are adapted
from the original private Ryoku NixOS project and the Keyitdev / MarianArlt
theme. The full GPLv3 license is in
`distro/LICENSES/GPL-3.0-or-later.txt`. The upstream Astronaut theme is
fetched separately on the Debian machine at pinned revision
`abb3163c724935af888ba5ea9ac0c4f22afd8048`, with its own upstream
license and assets. No private wallpapers are published.

## Generated / local files (not licensed as redistributable product)

- `distro/flake/hosts/<user>/default.nix` — generated/updated by bootstrap; staged with `git add` for pure flake eval (may be committed per machine)
- `flake.lock` — generated on guest by `nix flake lock` during `--apply`
- Backup trees under `/var/backups/ryoku-bootstrap-*`
