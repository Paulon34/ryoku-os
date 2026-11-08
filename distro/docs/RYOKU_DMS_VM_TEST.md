# Ryoku Debian — visual Quattro VM smoke test (ENTREGA B)

This is a **guest validation procedure**, not an assertion that DMS has
passed a GUI test. Run only after the PR #20 CI and pure Nix evaluation pass.
Do not modify Proxmox video hardware or erase the known-good Debian foundation.

## Confirm baseline (SSH, `paulo@ryoku-test`)

```bash
df -h /
systemctl is-active display-manager
pgrep -a -u paulo niri || true
```

Reserve room for DMS/Quickshell's Nix closure; if the root filesystem has
less than ~8 GiB available, do **not** proceed until disk usage is understood.
The Niri-only Entrega A already passed a manual QEMU/Proxmox guest test.

## Isolate the visual branch in a separate worktree

Keep `~/ryoku-os` (foundation) untouched. As the normal desktop user:

```bash
git -C ~/ryoku-os fetch origin cursor/debian-niri-desktop-port-88e9
git -C ~/ryoku-os worktree add --detach ~/ryoku-os-visual FETCH_HEAD
git -C ~/ryoku-os-visual rev-parse --short HEAD
```

Do not discard local `hosts/paulo/default.nix` or `flake.lock` from
`~/ryoku-os`. The new worktree is independent and the bootstrap generates
its own `hosts/paulo/default.nix`.

## Dry-run, then activate

```bash
cd ~/ryoku-os-visual
./distro/scripts/ryoku-bootstrap --dry-run --user paulo --profile minimal --visual balanced --shell-style quattro
sudo ./distro/scripts/ryoku-bootstrap --apply --user paulo --skip-apt --skip-nix --profile minimal --visual balanced --shell-style quattro
```

The installation builds patched DMS 1.5.3. It must complete the Home Manager
switch and `niri validate` before a graphical re-login. Do not claim success
if the package build or patch application fails. No new APT / Nix daemon
installation is needed on an already bootstrapped Debian guest.

## Test from GDM console

Log out and log back into **Ryoku (Niri)**. The Niri configuration now starts
`~/.local/bin/ryoku-start-dms` on session startup, which launches the patched
DMS through `nixGLIntel`. No competing `ryoku-dms.service` is enabled.

Check the visual shell, wallpaper, Quattro bar, launcher, widgets and whether
a Kitty window can be opened via Niri. If keyboard shortcuts fail inside
Proxmox noVNC, inspect the compositor from SSH:

```bash
pgrep -a -u paulo niri
pgrep -af 'dms|quickshell' || true
NIRI_SOCKET=$(find /run/user/$(id -u) -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)
NIRI_SOCKET="$NIRI_SOCKET" ~/.local/state/nix/profiles/home-manager/home-path/bin/niri msg outputs
NIRI_SOCKET="$NIRI_SOCKET" ~/.local/state/nix/profiles/home-manager/home-path/bin/niri msg windows
journalctl --user -b --no-pager | grep -Ei 'dms|quickshell|niri' | tail -80
```

A working Niri IPC response alone does **not** validate DMS, Quattro or
visual parity. Record a screenshot of the actual guest GUI and the relevant
logs before labeling `PASS_MANUAL` for Entrega B.

## Rollback to validated foundation

If the visual activation fails or cannot render, use the known-good foundation
bootstrap from the original worktree over SSH:

```bash
cd ~/ryoku-os
sudo ./distro/scripts/ryoku-bootstrap --apply --user paulo --skip-apt --skip-nix --profile minimal --visual balanced --shell-style quattro
```

Re-login through GDM and check Niri/Kitty again. Do not remove the new worktree
until logs have been retained. Do not reset Nix store, delete user HOME, change
GRUB or perform forced QEMU shutdown as part of this test.
