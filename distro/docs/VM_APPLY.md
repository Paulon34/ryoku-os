# VM apply procedure (Debian Modular / Hyprland)

Safe guest apply for Paulo's VM. **Do not** restart GDM/VM from an agent
session unless Paulo authorizes it. Preserve `flake.lock` and `hosts/paulo`.

## 1. Correct worktree

```bash
cd ~/ryoku-os-visual   # or your checkout
git fetch origin
# Stacked desktop-complete tip (Settings / doctor / apps) — preferred once merged to stack:
git checkout --detach origin/cursor/debian-desktop-complete-4fe6
# Or Hyprland stabilize tip only:
# git checkout --detach origin/cursor/debian-hyprland-primary-8dbd

test -f distro/flake/flake.lock && echo "KEEP flake.lock"
test -f distro/flake/hosts/paulo/default.nix && echo "KEEP hosts/paulo"
git rev-parse HEAD
```

## 2. Detect stale HM (red overlay root cause)

```bash
./distro/scripts/ryoku-doctor
# FAIL "STALE HM" means ~/.config/hypr/hyprland.conf still points at an old
# /nix/store/... generation while git tip moved — apply HM below.
readlink -f ~/.config/hypr/hyprland.conf
```

## 3. Bootstrap apply (preserve lock + host)

```bash
sudo ./distro/scripts/ryoku-bootstrap --apply --user paulo \
  --profile minimal --visual balanced --shell-style islands --compositor hyprland

# Never: nix flake update, discard hosts/paulo, uninstall Niri, force-push.
```

Bootstrap will:

- APT base (+ full if `--profile full`) and Hyprland backports (fail-closed)
- Keep existing `flake.lock`
- Rewrite/stage `hosts/paulo/default.nix` then `home-manager switch` as paulo
- Install GDM sessions (Hyprland + Niri recovery)
- Install Polkit policy + `/usr/local/libexec/ryoku-settings-apply` when built

## 4. Verify active store path + conf

```bash
./distro/scripts/ryoku-doctor
readlink -f ~/.config/hypr/hyprland.conf   # expect current /nix/store/...-home-manager-files/...
grep -E 'windowrule|layerrule' ~/.config/hypr/hyprland.conf | head
test -x ~/.local/bin/ryoku-start-dms
command -v ryoku-settings || echo "settings not on PATH yet"
```

## 5. After next Hyprland GUI login (Kitty inside session)

```bash
hyprctl configerrors          # expect empty
hyprctl layers                # expect Quickshell / dms:bar
hyprctl version | head -1     # ~0.55.x
./distro/scripts/ryoku-doctor
ryoku-settings &              # original Settings UI
```

## 6. Rollback

```bash
# Home Manager generation rollback (as paulo)
home-manager generations
home-manager switch --rollback
# or:
home-manager switch --flake ~/ryoku-os-visual/distro/flake#paulo --rollback

# Bootstrap file backups
ls /var/backups/ryoku-bootstrap-*
```

## Status vocabulary

| Code | Meaning |
|------|---------|
| `PASS_STATIC` | Repo/script checks without guest |
| `PASS_BUILD` | Nix/Qt build succeeded |
| `NOT_RUN` | Not executed in this agent |
| `NOT_TESTABLE_HERE` | Needs guest Wayland / APT / Nix daemon |
| `GUEST_NOT_RUN` | Guest session not exercised by agent |
| Never invent `PASS_MANUAL` / `PASS_GUEST` without guest evidence |
