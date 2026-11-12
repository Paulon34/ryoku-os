# VM apply procedure (Debian Modular / Hyprland)

Safe guest apply for Paulo's VM. **Do not** restart GDM/VM from an agent
session unless Paulo authorizes it. Preserve `flake.lock` and `hosts/paulo`.

## 0. Preconditions (before sudo apply)

1. Isolated worktree on the **exact tip** you intend to apply (PR #29 tip).
2. Preserve guest `flake.lock` and `hosts/paulo` (copy aside if the worktree is fresh).
3. Prefer: `nix build` / `home-manager build` for `.#paulo` when Nix is available.
4. `ryoku-bootstrap --dry-run` must pass.
5. Proxmox snapshot **before** `--apply`.

CI `PASS_STATIC` does **not** prove Qt/Nix build, graphical session, or Apply helper.

## 1. Correct worktree

```bash
# Example: dedicated worktree for this tip (adjust path to your layout)
cd ~
git fetch https://github.com/Paulon34/ryoku-os.git cursor/debian-desktop-complete-4fe6
# Or inside an existing clone:
cd /path/to/approved-checkout
git fetch origin
git checkout --detach origin/cursor/debian-desktop-complete-4fe6
git rev-parse HEAD   # expect the published tip SHA from the PR

# Preserve lock + host from the live guest tree if this worktree is new:
test -f distro/flake/flake.lock && echo "KEEP flake.lock" || echo "NEED lock from guest"
test -f distro/flake/hosts/paulo/default.nix && echo "KEEP hosts/paulo" || echo "bootstrap will write hosts/paulo"
```

Bootstrap records **`settingsApply.repoPath = <this REPO_ROOT>`** into `hosts/paulo`
so Settings Apply never targets a guessed `~/ryoku-os`.

## 2. Detect stale HM (red overlay root cause)

```bash
./distro/scripts/ryoku-doctor
# Reads ~/.local/state/ryoku/build-info.json first (mutable stamp; not an HM symlink).
# FAIL "STALE HM" → active generation commit ≠ worktree tip.
readlink -f ~/.config/hypr/hyprland.conf
```

## 3. Dry-run then apply

```bash
sudo ./distro/scripts/ryoku-bootstrap --dry-run --user paulo \
  --profile minimal --visual balanced --shell-style islands --compositor hyprland

# After Proxmox snapshot + dry-run OK:
sudo ./distro/scripts/ryoku-bootstrap --apply --user paulo \
  --profile minimal --visual balanced --shell-style islands --compositor hyprland

# Never: nix flake update, discard hosts/paulo, uninstall Niri, force-push, merge main.
```

## 4. Verify

```bash
./distro/scripts/ryoku-doctor
test -f ~/.local/state/ryoku/build-info.json && cat ~/.local/state/ryoku/build-info.json
grep -F repoPath distro/flake/hosts/paulo/default.nix   # must equal this checkout
readlink -f ~/.config/hypr/hyprland.conf
command -v ryoku-settings || echo "settings GUI not on PATH yet"
```

## 5. After next Hyprland GUI login

```bash
hyprctl configerrors
hyprctl layers
# Settings is nixGL-wrapped (Nix Qt6 + Debian Mesa). Prefer PATH launcher:
ryoku-settings &
# Debug without nixGL (expect EGL fail on Debian): ryoku-settings-unwrapped
# VM-only software RHI diagnostic (not a module default):
#   QT_QUICK_BACKEND=software ryoku-settings-unwrapped
./distro/scripts/ryoku-doctor
```

## 6. Rollback

```bash
home-manager generations
home-manager switch --rollback
# Generation switch in Settings uses profile activate (not flake rebuild).
```

## Status vocabulary

| Code | Meaning |
|------|---------|
| `PASS_STATIC` | Repo/script checks without guest |
| `PASS_BUILD` | Nix/Qt build succeeded |
| `NOT_RUN` / `NOT_TESTABLE_HERE` / `GUEST_NOT_RUN` | Not proven here |
| Never invent `PASS_MANUAL` / `PASS_GUEST` without guest evidence |
