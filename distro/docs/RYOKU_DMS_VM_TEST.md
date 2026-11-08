# Ryoku Debian — visual Quattro VM smoke test (ENTREGA B)

This is a **guest validation procedure**, not an assertion that DMS has
passed a GUI test. Run only after the PR #20 (or stacked visual fidelity PR)
CI and pure Nix evaluation pass. Do not modify Proxmox video hardware or erase
the known-good Debian foundation.

**Honesty:** Cloud agents without guest access must report `GUEST_NOT_RUN`.
Do not invent `PASS_MANUAL` without a screenshot of the Quattro bar.

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
# Prefer the visual-fidelity tip when present; else PR #20 head.
git -C ~/ryoku-os fetch origin cursor/debian-dms-visual-fidelity-81bd \
  || git -C ~/ryoku-os fetch origin cursor/debian-niri-desktop-port-88e9
git -C ~/ryoku-os worktree add --detach ~/ryoku-os-visual FETCH_HEAD
git -C ~/ryoku-os-visual rev-parse HEAD
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

### Alternate: Home Manager switch only (already bootstrapped)

```bash
cd ~/ryoku-os-visual/distro/flake
# Ensure hosts/paulo exists and is git-added (bootstrap does this).
home-manager switch --flake .#paulo
niri validate --config ~/.config/niri/config.kdl
```

## Test from GDM console

Log out and log back into **Ryoku (Niri)**. The Niri configuration starts
`~/.local/bin/ryoku-start-dms` on session startup, which launches the patched
DMS through `nixGLIntel` with `qs` + `dms` on PATH. No competing long-running
`ryoku-dms.service` is enabled (bar/session oneshots only).

### Visual checklist (screenshot required for PASS_MANUAL)

1. Quattro flat top bar visible (launcher, workspaces, clock, tray, notif, CC, battery)
2. Ryoku wallpaper (`ryoku-night.jpg` or Matugen-chosen)
3. Mod+Space launcher / spotlight; Mod+N notifications; Mod+X power menu
4. Mod+Return Kitty; Mod+E Thunar still work
5. `~/.config/niri/colors.kdl` exists (fallback or Matugen)

### SSH diagnostics (does **not** alone prove Quattro)

```bash
pgrep -a -u paulo niri
# Nix Quickshell often shows as .quickshell-wrapped — never use: pgrep -x quickshell
pgrep -af 'dms|quickshell|qs' || true
test -x ~/.local/bin/ryoku-start-dms && head -n 20 ~/.local/bin/ryoku-start-dms
command -v dms qs
type dms qs
test -f ~/.config/DankMaterialShell/settings.json \
  && jq '.barConfigs' ~/.config/DankMaterialShell/settings.json
# Expect array + visible:true / autoHide:false on id=default
jq '.barConfigs[] | select(.id=="default") | {id,visible,autoHide,leftWidgets}' \
  ~/.config/DankMaterialShell/settings.json
test -f ~/.config/niri/colors.kdl && head -n 20 ~/.config/niri/colors.kdl
ls -l ~/.config/ryoku/current-wallpaper ~/.local/share/wallpapers/ | head
NIRI_SOCKET=$(find /run/user/$(id -u) -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)
NIRI_SOCKET="$NIRI_SOCKET" ~/.local/state/nix/profiles/home-manager/home-path/bin/niri msg outputs
NIRI_SOCKET="$NIRI_SOCKET" ~/.local/state/nix/profiles/home-manager/home-path/bin/niri msg windows
journalctl --user -b --no-pager | grep -Ei 'dms|quickshell|niri|matugen' | tail -100

# IPC (needs qs on PATH — use HM profile or ryoku-dms-ipc; DMS shell.go execs "qs")
export PATH="$HOME/.local/bin:$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$HOME/.nix-profile/bin:$PATH"
which qs dms
dms ipc list
# Correct bar IPC (DMSShellIPC.qml): selector + value — NOT "bar reveal" alone
dms ipc call bar status index 0
dms ipc call bar reveal index 0
# Prefer the wrapper (always prepends qs):
~/.local/bin/ryoku-dms-ipc bar status index 0
# Do NOT mix qs ipc --pid with -p (Instance Selection excludes Config Selection).
# dgop missing ⇒ optional system-monitor metrics only; does not hide the bar.

# Optional screenshot from the guest (save under Pictures):
# grim ~/Pictures/Screenshots/entrega-b-quattro-$(date +%Y%m%d-%H%M%S).png
```

Confirm `barConfigs` is a **JSON array** with `"id":"default"` and Quattro
`leftWidgets` / `centerWidgets` / `rightWidgets`. An object map means the
seed/merge did not apply.

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

## Known Hyprland → Niri limits

| Item | Hyprland (ryoku-desktop) | Niri (Debian) |
|------|--------------------------|---------------|
| Quattro custom workspace strip | `Hyprland.*` QML | Stock DMS workspaceSwitcher (patch gates on `isHyprland`) |
| Video wallpaper | hypr/mpv helpers | Static Matugen wallpaper only |
| SDDM astronaut | Ported QML | GDM remains |
| Hyprland border gradient | Matugen hypr conf | Niri focus-ring via `colors.kdl` |
