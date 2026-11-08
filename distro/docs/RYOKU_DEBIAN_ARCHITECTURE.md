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

`distro/flake/` exposes `homeConfigurations.<user>` from **`hosts/<user>/default.nix`**
(plain attrsets with `username`, `homeDirectory`, `profile`). Bootstrap writes that
file and `git add`s it so pure flakes see it — **no gitignored overlay**.

```bash
home-manager switch --flake ./distro/flake#alice   # as user alice
```

Modules under `distro/flake/home/` **must not** reference `osConfig` / NixOS options.
System concerns (DM, NM, PipeWire packages) stay on APT + systemd.
HM switch always runs as `--user` so `$HOME` is correct and not root-owned.


## Graphics

Host Mesa from APT. Nix-built GL/Vulkan apps should use `ryoku-nixgl` (nixGL) wrappers installed by HM.

## Profiles (ENTREGA C+)

Combinable axes (not mutually exclusive “SKU” silos):

| Axis | Values | Notes |
|------|--------|-------|
| `edition` | minimal / full | Package breadth |
| `visual` | lite / balanced / ultra | Perf/visual budget for DMS |
| `shellStyle` | quattro / islands | DMS patched look |
| `jarvis` | bool (default off) | Bridge opt-in |
| `compositor` | niri (only wired) / hyprland (reserved) | See `COMPOSITOR.md` |

Future labels like developer/server/security should be **feature sets on top of these axes**, not a second parallel matrix that forks the desktop stack.

## Session ownership

See `SERVICE_OWNERSHIP.md`. DMS owns notifications; Niri spawns NM/polkit/cliphist/DMS; PipeWire stays systemd --user at login.

## Nix future

Current **Architecture A (hybrid APT + Nix HM)** is the stabilization target. Removing Nix (Architecture B) or a refined hybrid (C) is a **future decision** — do not strip Nix while Quattro/desktop is still guest-unproven. See master audit report.

## Live ISO (ENTREGA E)

`live-build` + Calamares only after the desktop session works. VMs are discard-only.

## Related upstream

Visual/UX reference: [Paulon34/ryoku-desktop](https://github.com/Paulon34/ryoku-desktop) (Hyprland + DMS + Material You). Port matrix: `docs/migration/HYPRLAND_TO_NIRI_KEYBINDS.md`.
