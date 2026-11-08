# Ryoku Debian Architecture (ENTREGA A+)

## Goal

Ship a **usable Debian 13 Trixie amd64** guest with:

- APT base (NetworkManager, PipeWire, portals, polkit, GDM, Kitty, Thunar, Fuzzel, Mesa/XWayland)
- **Nix multi-user** via Debian packages `nix-bin` + **`nix-setup-systemd`** (real in Trixie)
- **Home Manager standalone** flake (no `osConfig`, no NixOS modules)
- **Niri** from nixpkgs (no Debian `niri` package in Trixie → Nix pin)
- Wayland session entry `Ryoku (Niri)` for GDM

Experimental Rust desktop PRs `#6`–`#18` are **preserved** and **out of scope** for this track.

## Layering

```
┌─────────────────────────────────────────────┐
│  Apps (Kitty/Thunar/Fuzzel APT + Nix extras)│
├─────────────────────────────────────────────┤
│  Shell/UI (DMS 1.5.3 + Ryoku patches = B)   │
├─────────────────────────────────────────────┤
│  Niri (Nix) + XWayland + Matugen colors     │
├─────────────────────────────────────────────┤
│  Home Manager standalone flake              │
├─────────────────────────────────────────────┤
│  Nix daemon (nix-setup-systemd)             │
├─────────────────────────────────────────────┤
│  Debian 13 userland (APT)                   │
└─────────────────────────────────────────────┘
```

## Bootstrap contract

Entry: `distro/scripts/ryoku-bootstrap`

| Flag | Behavior |
|------|----------|
| `--dry-run` | Print plan; no durable host mutations. Allowed on non-Debian developer hosts. |
| `--apply` | Mutate a **Debian 13** system (root required for `/`). |

Hard refuses:

- NixOS (`/etc/NIXOS`)
- GRUB / EFI / partition changes
- Inventing `PASS_MANUAL`
- Auto QEMU

After apply alone, guest desktop status remains **`GUEST_NOT_RUN`** until a human verifies the session.

## Home Manager standalone

`distro/flake/` is a flake exposing `homeConfigurations.ryoku`. Modules under `distro/flake/home/` **must not** reference `osConfig` or NixOS options. System concerns (DM, NM, PipeWire packages) stay on APT + systemd.

## Graphics

Host Mesa from APT. Nix-built GL/Vulkan apps should use `ryoku-nixgl` (nixGL) wrappers installed by HM.

## Profiles (ENTREGA C)

Lite / Balanced / Ultra × Minimal / Full — shared modules under `distro/flake/modules/` (stub in A).

## Live ISO (ENTREGA E)

`live-build` + Calamares only after the desktop session works. VMs are discard-only.

## Related upstream

Visual/UX reference: [Paulon34/ryoku-desktop](https://github.com/Paulon34/ryoku-desktop) (Hyprland + DMS + Material You). Port matrix: `docs/migration/HYPRLAND_TO_NIRI_KEYBINDS.md`.
