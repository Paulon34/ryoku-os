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
| Multi-monitor | One mpvpaper instance, `OUTPUTS=ALL` |
| Fail → static | `ExecCondition` / missing file keeps DMS poster/static |
| Decode | `hwdec=vaapi` + `gpu-hwdec-interop=vaapi` (Intel preferred; avoid NVIDIA wake) |
| Profiles | economy≈15fps, balanced≈30fps, quality=source |
| Pause | `--auto-pause` when covered (fullscreen / lock) when enabled |
| Matugen | One poster frame → `matugen image … --mode dark` (never flip light) |

## systemd (GDM-safe)

- **Path unit** `ryoku-video-wallpaper.path` is `WantedBy=default.target` and
  starts the service when `video-wallpaper.env` exists.
- **Service** has **no** `WantedBy=default.target` and **no**
  `After=default.target` (that pairing cycles under user systemd).
- `KillMode=control-group`, `ExecStop=stop-orphans`, `StartLimitBurst=3`,
  apply uses stop→orphan-sweep→start (not bare restart).

## Guest checks (after HM build + switch)

```sh
command -v ryoku-video-wallpaper mpvpaper ffmpeg ffprobe
systemctl --user cat ryoku-video-wallpaper.service | rg 'After=|WantedBy=|KillMode|ExecStop'
systemctl --user status ryoku-video-wallpaper.service ryoku-video-wallpaper.path
ryoku-video-wallpaper status
# From Settings → Appearance → Video: pick a local gallery file, Apply
# Restore static: Appearance → Image → select wallpaper
# Orphans: pgrep -x mpvpaper  # should be empty after stop
```

Live Hyprland/mpvpaper = **NOT_TESTED** from cloud agents.
