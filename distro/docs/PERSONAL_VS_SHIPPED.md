# Personal vs shipped config (Debian Modular)

Pulls must not fight your live desktop prefs or guest Nix lock.

| Path | Role | Pull-safe? |
|------|------|------------|
| `distro/ryoku/settings.json` | Clean first-install seed | Yes (shipped) |
| `ryoku/settings.json` (repo root) | GUI live file Settings writes | **Personal** — can dirty the worktree |
| `~/.config/ryoku/settings.json` | HM seed if missing; DMS watches related keys | Seed only once |
| `distro/flake/flake.lock` | Guest-tested pin | **Preserve** — bootstrap already refuses unnecessary updates |
| Host overlays / `hosts/paulo` | Machine-local | Never overwritten by public seed |

## Safe pull around dirty `settings.json`

```sh
cd ~/ryoku-os   # or your worktree
# Option A — keep local prefs across pull (recommended on the daily driver):
git update-index --skip-worktree ryoku/settings.json
git update-index --skip-worktree distro/flake/flake.lock  # if you maintain a guest lock

git fetch origin cursor/debian-full-hardware
git pull --ff-only origin cursor/debian-full-hardware

# Inspect what Settings still has:
jq '.appearance|{wallpaper,wallpaperType,videoWallpaper,shellStyle}' ryoku/settings.json

# HM as desktop user (never root):
home-manager switch --flake "$PWD/distro/flake#$USER"
```

Helper (same skip-worktree marks):

```sh
bash distro/scripts/ryoku-preserve-local mark
bash distro/scripts/ryoku-preserve-local status
```

## What Ryoku will not do

- Overwrite an existing `~/.config/ryoku/settings.json` on HM activation
- Commit private wallpapers, videos, drivers, or credentials
- Force `nix flake update` during bootstrap when a lock already exists
