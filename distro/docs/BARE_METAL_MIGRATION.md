# Bare-metal migration procedure (Debian 13 only)

**Scope:** migrate a working Debian 13 amd64 install to Ryoku Modular
(Hyprland primary + Niri recovery). **Out of scope:** disk partitioning, EFI
install, dual-boot surgery, NixOS install, ISO live installer (Entrega E).

## Preconditions

- Debian 13 (Trixie) amd64 with working network and a non-root desktop user
- Backups of `~/.config`, wallpapers, and any secrets (do not copy private
  NixOS host trees into the public repo)
- Optional: export allowlisted prefs from `ryoku-desktop` / NixOS **with user
  consent only**

## Steps

1. Clone `Paulon34/ryoku-os` to `~/ryoku-os` (or keep an existing worktree).
2. `cd ~/ryoku-os && git fetch && git checkout <stacked tip>` (see `VM_APPLY.md`).
3. Confirm `distro/flake/flake.lock` exists — **preserve** it.
4. Dry-run:

   ```bash
   sudo ./distro/scripts/ryoku-bootstrap --dry-run --user "$USER" \
     --profile minimal --visual balanced --shell-style islands --compositor hyprland
   ```

5. Apply (will use sudo for APT/Nix/GDM; HM runs as `$USER`):

   ```bash
   sudo ./distro/scripts/ryoku-bootstrap --apply --user "$USER" --yes \
     --profile minimal --visual balanced --shell-style islands --compositor hyprland
   ```

6. Log out and select **Ryoku (Hyprland)** in GDM. Keep **Ryoku (Niri)** as recovery.
7. Inside the session: `./distro/scripts/ryoku-doctor`, `hyprctl configerrors`, `hyprctl layers`.
8. Open **Ryoku Settings** for wallpaper / appearance; Matugen persists via
   `~/.config/ryoku/current-wallpaper` + templates.

## Package ownership

| Concern | Method |
|---------|--------|
| Hyprland, portals, guiutils | APT trixie-backports |
| Kitty, Thunar, Firefox ESR, Flatpak, fonts | APT (`packages-base` / `packages-full`) |
| Niri, DMS, Quickshell, Matugen, nixGL, Settings | Nix / Home Manager |
| NM, PipeWire, polkit, GDM | APT + systemd |

## Do not

- Run `nix flake update` on a guest-tested lock without intent
- Discard `hosts/<user>/default.nix`
- Uninstall Niri recovery
- Copy private `ryoku-nixos` secrets into this public tree
- Partition disks or rewrite EFI from bootstrap
