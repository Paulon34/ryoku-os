# Personal vs shipped config (Debian Modular)

Pulls must not fight your live desktop prefs or guest Nix lock.

| Path | Role | Pull-safe? |
|------|------|------------|
| `distro/ryoku/settings.json` | Clean first-install seed | Yes (shipped) |
| `ryoku/settings.json` (repo root) | GUI live file Settings writes | **Personal** — can dirty the worktree |
| `~/.config/ryoku/settings.json` | HM seed if missing; DMS watches related keys | Seed only once |
| `distro/flake/flake.lock` | Guest-tested pin | **Preserve** — bootstrap already refuses unnecessary updates |
| Host overlays / `hosts/paulo` | Machine-local | Never overwritten by public seed |

## Safe pull / apply (backup, not skip-worktree)

`git update-index --skip-worktree` is **not** personal-config protection — it
hides dirty state and surprises later pulls. Use a real backup first:

```sh
cd ~/ryoku-os   # or your worktree
bash distro/scripts/ryoku-preserve-local backup
bash distro/scripts/ryoku-preserve-local status

git fetch origin cursor/debian-full-hardware
git checkout cursor/debian-full-hardware
git pull --ff-only origin cursor/debian-full-hardware
git rev-parse HEAD

# Inspect prefs after pull (restore from stamp if a pull overwrote them):
jq '.appearance|{wallpaper,wallpaperType,videoWallpaper,shellStyle}' ryoku/settings.json
# bash distro/scripts/ryoku-preserve-local list
# bash distro/scripts/ryoku-preserve-local restore <stamp>

# Always build before switch (desktop user — never root):
home-manager build --flake "$PWD/distro/flake#$USER"
home-manager switch --flake "$PWD/distro/flake#$USER"

# Or one helper that backups + build + switch:
# bash distro/scripts/ryoku-preserve-local hm-apply
```

Backups land under `~/.local/state/ryoku/prefs-backup/<UTC-stamp>/`.

## What Ryoku will not do

- Overwrite an existing `~/.config/ryoku/settings.json` on HM activation
- Commit private wallpapers, videos, drivers, or credentials
- Force `nix flake update` during bootstrap when a lock already exists
- Recommend skip-worktree as a substitute for backups
