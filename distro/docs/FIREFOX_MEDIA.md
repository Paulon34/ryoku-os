# Firefox / YouTube CPU — investigation (Debian Ryoku)

Cloud agents cannot measure guest CPU. Use these **read-only** checks on the
notebook. Do **not** disable security features (`security.sandbox`, Widevine
bypass hacks, or unsigned add-ons).

## Investigation commands

```sh
# Process + compositor class
ps -o pid,pcpu,pmem,cmd -C firefox-esr | head
hyprctl clients 2>/dev/null | rg -i 'firefox|class' || true

# VA-API / Intel media (iGPU) — presence only
vainfo 2>&1 | head -40
ls /dev/dri/
# Flatpak Firefox (if used):
flatpak info org.mozilla.firefox 2>/dev/null | head
flatpak run --command=sh org.mozilla.firefox -c 'echo MOZ_DISABLE_RDD_SANDBOX=$MOZ_DISABLE_RDD_SANDBOX' 2>/dev/null || true

# About:support (manual): search "HARDWARE_VIDEO_DECODING", "Compositing", "WebRender"
```

## Safe config (optional)

APT `firefox-esr` already gets Wayland via session `MOZ_ENABLE_WAYLAND=1`.

If `vainfo` shows Intel VA entrypoints and YouTube still burns CPU:

1. `about:config` → confirm `media.ffmpeg.vaapi.enabled` is `true` (ESR defaults vary).
2. Prefer **hardware decoding** in Settings → General → Performance (leave
   recommended limits unless diagnosing).
3. Close unused heavy tabs; Picture-in-Picture still decodes.

Do **not** set `MOZ_DISABLE_RDD_SANDBOX=1` or disable `media.rdd-process.enabled`
for day-to-day use.

## Hybrid NVIDIA

Prefer Intel VA-API for browser decode. Forcing NVDEC for Firefox can wake the
dGPU and raise power/thermals — out of scope unless you intentionally offload.
