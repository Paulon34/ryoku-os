# Live video wallpaper (Debian Modular)

**Backend:** `mpvpaper` via `ryoku-video-wallpaper` (ported from private
`ryoku-nixos` public logic only — no private videos).

## Behaviour

| Feature | Behaviour |
|---------|-----------|
| Formats | `.mp4` `.webm` `.mkv` `.mov` (gallery basename) |
| Loop / mute | Loop default on; audio default off |
| Preview | Poster frame in Settings (no live decode in the GUI) |
| On/off | Appearance → Video apply / Image restore; `ryoku-video-wallpaper stop` |
| Persist | `~/.local/state/ryoku/video-wallpaper.env` + `appearance.videoWallpaper` |
| Arm file | `video-wallpaper.want` — PathExists watches **this**, not `.env` |
| Multi-monitor | One mpvpaper instance, `OUTPUTS=ALL` (independent pause needs per-output instances — not default) |
| Fail → static | `ExecCondition` / missing file / disarmed keeps DMS poster/static |
| Decode | `hwdec=vaapi` + `gpu-hwdec-interop=vaapi` (Intel preferred; avoid NVIDIA wake) |
| Profiles | economy≈15fps, balanced≈30fps, quality=source |
| Pause | Native `--auto-pause --auto-mode MAX` plus smart controller SIGSTOP |
| Unload | Disarm `.want` **first**, then stop mpvpaper; restore DMS poster |
| Resume | Controller/`reload` re-arms `.want` then starts — **no** Matugen |
| Coverage | Scale-aware geometry; side-by-side union ≥85%; per-monitor independent |
| Media policy | `off` (default) / `video` / `all` |
| Matugen | **Once** on `apply`; stamp in `video-wallpaper-palette.stamp` |

## Why `.want` (PathExists fix)

Keeping only `video-wallpaper.env` after unload caused the path unit to
re-start mpvpaper while the controller still considered the wallpaper unloaded.
Unload now **disarms** `.want` before stopping the unit; reload/apply alone
re-arm. `ExecCondition` also refuses start when disarmed.

## Smart controller + HIS

- Unit: `ryoku-video-wallpaper-smart.service` (`watch`)
- Hyprland exports `HYPRLAND_INSTANCE_SIGNATURE` via `dbus-update` +
  `systemctl --user import-environment`; units `PassEnvironment` it; helper
  also discovers `$XDG_RUNTIME_DIR/hypr/*/`.
- Commands: `coverage` `pause` `unpause` `unload` `reload` `watch` `status`

## systemd (GDM-safe)

- Renderer **path** watches `%S/ryoku/video-wallpaper.want` (`WantedBy=default.target`).
- Smart **path** watches `%S/ryoku/video-wallpaper.env`.
- Services have **no** `WantedBy=default.target` / **no** `After=default.target`.
- `KillMode=control-group`, `ExecStop=stop-orphans`, apply uses stop→arm→start.

## Guest apply / rollback

```sh
# Backup personal prefs first
bash distro/scripts/ryoku-preserve-local backup

cd ~/ryoku-os
git fetch origin cursor/debian-full-hardware
git checkout cursor/debian-full-hardware
git pull --ff-only origin cursor/debian-full-hardware
git rev-parse HEAD   # must match reported tip

home-manager build --flake "$PWD/distro/flake#$USER"
home-manager switch --flake "$PWD/distro/flake#$USER"
# or: bash distro/scripts/ryoku-preserve-local hm-apply

# Smoke
ryoku-settings-launcher-check
ryoku-video-wallpaper status   # armed=0|1
ryoku-video-wallpaper coverage
systemctl --user cat ryoku-video-wallpaper.service | rg 'ConditionPathExists|PassEnvironment'
```

Rollback (exact previous tip SHA):

```sh
git -C ~/ryoku-os fetch origin cursor/debian-full-hardware
git -C ~/ryoku-os checkout <previous-sha>
bash distro/scripts/ryoku-preserve-local hm-apply
# Manual desktop backups if any: ~/.local/state/ryoku/desktop-backup/
```

Live Hyprland/mpvpaper = **NOT_TESTED** from cloud agents.
