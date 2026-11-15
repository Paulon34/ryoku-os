# Ryoku Desktop — Performance & Polish

Daily driver: Debian 13, Hyprland 0.55.2, DMS 1.5.3, Quattro / Islands, hybrid Intel Iris Xe + GTX 1650. Preserve the working nixGLIntel renderer, Matugen dark, GDM, NVIDIA, CUPS and private media.

## Observed baseline (one snapshot, not a benchmark)
CPU idle 76.7%; available memory 9223.6 MiB; swap used 1.2 MiB. top process CPU is relative to one logical CPU: Firefox 76.6%, Hyprland 18.9%, mpvpaper 7%, Quickshell 2%. Quickshell RSS 753208 KiB, mpvpaper RSS 367844 KiB. Use PSS and repeated samples rather than summing RSS. User has manually created the canonical desktop entry because the expected HM entry was missing. CAVA installed natively.

## 1. Launcher
Find the actual XDG dataHome and DMS/Quickshell process environment. Verify canonical org.ryoku.Settings.desktop, stable ~/.local/bin/ryoku-settings Exec/TryExec, valid icon and search keywords. Use desktop-file-validate and gio launch; inspect DMS app discovery and cache. Adopt/backup the existing manual entry without clobbering it, one canonical managed ID, no duplicate entries. Test search and actual launch after HM switch and fresh login. Preserve SUPER+I.

## 2. Intelligent wallpaper
Existing native mpvpaper auto-pause is best effort. The MAX mode additionally detects maximized windows where supported, but is not a per-monitor visibility guarantee. Pause reduces decoding/rendering load, not necessarily RSS. For substantial memory savings implement unload to static DMS poster, then resume when appropriate. Prefer event-driven compositor IPC with debouncing. Inspect actual mpvpaper version/holder behavior; do not assume ALL can independently pause outputs. For independent outputs, use one managed instance per necessary output only if measurements and correct IPC justify it. Avoid duplicate daemons. Test normal, maximized and fullscreen windows, tiled coverage, workspace switches, both outputs, hotplug, DPMS, lock/unlock, battery/AC and media playback. In balanced mode, if a video is playing in the foreground and the wallpaper is covered, pause that output; preserve animation on visible output if possible. Provide a configurable global media policy (video or all media, off by default for audio-only). Economic mode: pause covered outputs immediately; after configurable grace (e.g. 20s) stop decoding and restore static poster; release renderer allocations. Balanced: short pause and unload on prolonged coverage (e.g. 60s), battery configurable. Quality: preserve visible animation; still pause for games/lock if enabled. Use hysteresis, no repeated palette generation on resume, no aggressive killing. Make unsupported compositor state degrade safely. Maintain Niri recovery. Do not touch the user's selected file.

## 3. CAVA
Reuse the actual pinned DMS audio service API, inspect upstream QML from the pinned derivation. Integrate real shared spectrum into Media Island, compact popout and expanded player for Quattro and Islands. One audio sampler only if possible, gated by visible consumers and MPRIS Playing; 20–30 FPS initial target, no fake data, no constant polling in silence. Hide or settle when paused. Match dynamic colors, compact layout, accessibility/reduced motion. Native CAVA is declared in base APT. Confirm actual command resolution in DMS PATH; no duplicate package install unless necessary.

## 4. Firefox and compositor performance
Use about:support, codec support, vainfo and intel_gpu_top to determine actual hardware decode; avoid disabling sandbox or forcing unsupported options. Compare identical video content and monitor refresh rates. Inspect Hyprland monitors/clients/layers and Quickshell timers, loaders, artwork caches, animations and duplicate instances. Preserve visual quality. Inspect PSS via /proc/PID/smaps_rollup for user processes, sample top CPU repeatedly, record battery/power where supported. Compare static, video visible, covered, paused, unloaded, and resume; repeat with two outputs and foreground video. Record actual results and uncertainty, not fabricated percentage reductions. Avoid routine NVIDIA polling waking sleeping dGPU; identify GPU usage, VRAM, temperature and power only from supported interfaces; distinguish unavailable/asleep.

## 5. Deployment and acceptance
Use local notebook access for runtime checks. Backup personal settings, flake.lock, host and manual desktop entry; never commit private data. Build HM before switch, use existing pins and backup suffix; avoid global changes, no reboot/logout without authorization, no merge. Do not modify drivers or GDM. Validate all static tests and report CI, then individually label PASS_REAL, PASS_STATIC, PARTIAL, FAIL, NOT_TESTED. Keep selected wallpaper, Matugen palette, printers, theme and launcher working. Commit small independent changes; report before/after and exact rollback.

## Implementation status (code on `cursor/debian-full-hardware`)

Shipped in-tree (cloud-verifiable as **PASS_STATIC** only):

1. Launcher — absolute Exec/TryExec, adopt/backup manual desktop, `ryoku-settings-launcher-check`, X-Ryoku-Managed marker.
2. Smart wallpaper — `pause`/`unload`/`reload`/`watch`/`coverage`; grace by profile; no rematugen on resume; smart systemd unit.
3. CAVA — APT `cava` + `ryoku-media-cava.patch` on Media Island / Mini Player via shared `CavaService`; `audioVisualizerEnabled=true`.
4. Firefox — expanded `FIREFOX_MEDIA.md` (safe prefs only).
5. Dual-monitor — Hyprland `vfr=true`, blur passes capped, dual-monitor comments; DMS bar `showOnLastDisplay`.
6. GPU sensors — Intel drm sysfs + one-shot `nvidia-smi` (or asleep/unavailable); no bar GPU widgets claimed.
7. Power — `ryoku-power-policy` + user timer (battery → economy tip).

Notebook/live Hyprland, mpvpaper RSS, Firefox VA-API, launcher search, CAVA frames = **NOT_TESTED** until guest validation.
