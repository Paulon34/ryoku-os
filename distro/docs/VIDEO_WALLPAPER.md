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
| Multi-monitor | One mpvpaper instance, `OUTPUTS=ALL` (independent per-output pause needs separate instances — not default) |
| Fail → static | `ExecCondition` / missing file keeps DMS poster/static |
| Decode | `hwdec=vaapi` + `gpu-hwdec-interop=vaapi` (Intel preferred; avoid NVIDIA wake) |
| Profiles | economy≈15fps, balanced≈30fps, quality=source |
| Pause | Native `--auto-pause --auto-mode MAX` plus smart controller SIGSTOP |
| Unload | After grace (economy 20s / balanced 60s / quality never): stop mpvpaper, restore DMS poster |
| Resume | `reload` starts mpvpaper **without** Matugen / Material You regeneration |
| Media policy | `off` (default) / `video` / `all` — pause when fullscreen media matches |
| Matugen | **Once** on `apply` (poster → `matugen image … --mode dark`); stamp in `video-wallpaper-palette.stamp` |

## Smart controller

- Unit: `ryoku-video-wallpaper-smart.service` (`ryoku-video-wallpaper watch`)
- Hyprland `socket2` via `socat` when available; else 2s poll
- Coverage via `hyprctl -j monitors/clients` (fullscreen / ≥85% area / lock)
- Unload only when **all** outputs are covered (single ALL instance)
- Niri recovery: coverage probe returns uncovered → no forced unload
- Commands: `coverage` `pause` `unpause` `unload` `reload` `watch`

## systemd (GDM-safe)

- **Path unit** `ryoku-video-wallpaper.path` is `WantedBy=default.target` and
  starts the service when `video-wallpaper.env` exists.
- **Service** has **no** `WantedBy=default.target` and **no**
  `After=default.target` (that pairing cycles under user systemd).
- Smart path/service mirrors the same pattern (path WantedBy default.target).
- `KillMode=control-group`, `ExecStop=stop-orphans`, `StartLimitBurst=3`,
  apply uses stop→orphan-sweep→start (not bare restart).

## Guest checks (after HM build + switch)

```sh
command -v ryoku-video-wallpaper mpvpaper ffmpeg ffprobe socat
systemctl --user cat ryoku-video-wallpaper.service | rg 'After=|WantedBy=|KillMode|ExecStop'
systemctl --user status ryoku-video-wallpaper.service ryoku-video-wallpaper-smart.service
ryoku-video-wallpaper status
ryoku-video-wallpaper coverage
# From Settings → Appearance → Video: pick a local gallery file, Apply
# Cover with fullscreen → pause; wait grace → unload (pgrep -x mpvpaper empty)
# Uncover → reload without rematugen (palette stamp mtime unchanged)
# Restore static: Appearance → Image → select wallpaper
```

Live Hyprland/mpvpaper = **NOT_TESTED** from cloud agents.
