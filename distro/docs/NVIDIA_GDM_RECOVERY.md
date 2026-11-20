# NVIDIA + GDM recovery notes (documentation only)

**This tree does not install or change NVIDIA drivers, GDM defaults, or session
kill paths.** Use these notes on the bare-metal host when diagnosing Wayland /
login failures after an optional proprietary stack.

## Repositories

```sh
# contrib + non-free(-firmware) must be enabled for Debian nvidia packages
grep -REhn 'contrib|non-free' /etc/apt/sources.list /etc/apt/sources.list.d/ || true
sudo apt update
apt-cache policy nvidia-detect nvidia-driver
```

## Detect / DKMS / DRM (read-only until you choose to install)

```sh
nvidia-detect            # recommendation only
uname -r
dpkg -l | rg 'nvidia|linux-headers'
# After an install YOU performed: DKMS build status
dkms status 2>/dev/null || true
lsmod | rg 'nvidia|nouveau'
# DRM nodes
ls -l /dev/dri/
```

Driver install remains an explicit `--nvidia-driver` bootstrap path (see
`FULL_HARDWARE.md`). Do not treat APT success as Wayland proof.

## GDM Wayland recovery

When GDM fails to start a Wayland session after proprietary NVIDIA changes,
Debian often documents disabling Wayland in GDM:

```sh
# Inspect only first:
ls -l /etc/gdm3/custom.conf /run/gdm3/custom.conf 2>/dev/null || true
# Recovery (host admin): WaylandEnable=false under [daemon] in the active
# custom.conf — prefer a local override drop-in when your site uses one.
# Example pattern used on some hosts (do not invent paths blindly):
#   /etc/gdm3/custom.conf
#   /run/gdm3/custom.conf   # runtime; may reset
```

Local udev/rules overrides such as `61-gdm.rules` are **site-specific**. Copy
or edit them only from your private notes; never commit host rules or
credentials here.

## PRIME / offload

Automatic PRIME configuration is out of scope. Hybrid Intel/NVIDIA wallpaper
and browser paths prefer the iGPU (VA-API) so the dGPU can stay asleep.
