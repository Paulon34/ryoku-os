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
| PipeWire / WirePlumber | Audio (APT) | MIT / LGPL |
| NetworkManager | Networking (APT) | GPL-2.0-or-later |
| xdg-desktop-portal (+ gtk/wlr) | Portals (APT) | LGPL-2.1+ |
| polkit | Privilege broker (APT) | LGPL-2.0+ |
| Mesa / XWayland | Graphics (APT) | MIT / X11-style |
| xwayland-satellite | XWayland helper (Nix) | MPL-2.0 |

## Visual / UX reference (ENTREGA B+)

[Paulon34/ryoku-desktop](https://github.com/Paulon34/ryoku-desktop) (MIT for original Ryoku code; see that repo’s `THIRD_PARTY_NOTICES.md` for DMS patches, SDDM astronaut GPL-3.0-or-later QML, Material Symbols Apache-2.0, Omarchy behaviour reference MIT).

ENTREGA A only adapts **keybind intent** and architecture notes — no DMS patch files are copied yet.

## Generated / local files (not licensed as redistributable product)

- `distro/flake/hosts/<user>/default.nix` — generated/updated by bootstrap; staged with `git add` for pure flake eval (may be committed per machine)
- `flake.lock` — generated on guest by `nix flake lock` during `--apply`
- Backup trees under `/var/backups/ryoku-bootstrap-*`
