# Firefox / YouTube CPU — investigation (Debian Ryoku)

Cloud agents cannot measure guest CPU. Use these **read-only** checks on the
notebook. Do **not** disable security features (`security.sandbox`, Widevine
bypass hacks, or unsigned add-ons).

## Investigation commands

```sh
# Process + compositor class
ps -o pid,pcpu,pmem,rss,cmd -C firefox-esr | head
# Prefer PSS when diagnosing RAM (RSS double-counts shared):
pid=$(pgrep -n firefox-esr || true)
[[ -n "$pid" ]] && awk '/^Pss:/{s+=$2} END{printf "Firefox PSS KiB: %s\n", s+0}' /proc/$pid/smaps_rollup

hyprctl clients 2>/dev/null | rg -i 'firefox|class' || true

# VA-API / Intel media (iGPU) — presence only
vainfo 2>&1 | head -40
ls /dev/dri/
# intel_gpu_top (optional APT intel-gpu-tools) — short sample, Ctrl-C
# sudo intel_gpu_top -s 1000 | head

# Flatpak Firefox (if used):
flatpak info org.mozilla.firefox 2>/dev/null | head
flatpak run --command=sh org.mozilla.firefox -c 'echo MOZ_DISABLE_RDD_SANDBOX=$MOZ_DISABLE_RDD_SANDBOX' 2>/dev/null || true

# About:support (manual): search "HARDWARE_VIDEO_DECODING", "Compositing", "WebRender"
# about:support → Media → Codec Support / Hardware Decoding
```

## Safe config (optional)

APT `firefox-esr` already gets Wayland via session `MOZ_ENABLE_WAYLAND=1`.

If `vainfo` shows Intel VA entrypoints and YouTube still burns CPU:

1. `about:config` → confirm `media.ffmpeg.vaapi.enabled` is `true` (ESR defaults vary).
2. Prefer **hardware decoding** in Settings → General → Performance (leave
   recommended limits unless diagnosing).
3. Keep `media.rdd-process.enabled` = `true` (default).
4. Close unused heavy tabs; Picture-in-Picture still decodes.
5. Match monitor refresh: 60 Hz content on a 60 Hz panel avoids pointless
   compositor overwork; do not force higher `layout.frame_rate` overrides.

Optional user.js / prefs **only if VA-API is confirmed working** (never ship
forced prefs that break sandbox):

| Pref | Safe value | Notes |
|------|------------|-------|
| `media.ffmpeg.vaapi.enabled` | `true` | Intel VA-API decode |
| `widget.dmabuf.force-enabled` | leave default | Only if diagnosing dmabuf |
| `gfx.webrender.all` | leave default | WebRender is expected on Wayland |

Do **not** set `MOZ_DISABLE_RDD_SANDBOX=1` or disable `media.rdd-process.enabled`
for day-to-day use. Do **not** set `media.hardware-video-decoding.force-enabled`
unless `about:support` already proves codecs and you are debugging a false negative.

## Hybrid NVIDIA

Prefer Intel VA-API for browser decode. Forcing NVDEC for Firefox can wake the
dGPU and raise power/thermals — out of scope unless you intentionally offload.

## Acceptance labels

| Check | Cloud | Notebook |
|-------|-------|----------|
| Docs + safe prefs table | PASS_STATIC | — |
| vainfo / about:support / CPU before-after | NOT_TESTED | guest |
