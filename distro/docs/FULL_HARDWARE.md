# Ryoku Full — Debian 13 workstation migration

The Full edition is additive. Minimal keeps browser, file manager, terminal, archive/image tools, Wayland desktop, network/audio and Flatpak support; both editions share automatic hardware discovery. Full adds the workstation packages and applications declared in the original Ryoku NixOS modules. Package names are mapped to Debian/Flathub; this is not a binary clone of NixOS.

## First run

On Debian 13 amd64, from the reviewed project checkout (not NixOS):

```sh
bash distro/scripts/ryoku-hardware
bash distro/scripts/ryoku-bootstrap --dry-run --user "$USER" --profile full --hardware auto --visual auto --shell-style quattro
```

Only after a backup, working recovery console and package review:

```sh
sudo bash distro/scripts/ryoku-bootstrap --apply --user "$USER" --profile full --hardware auto --visual auto --shell-style quattro
```

The same auto probe works with Minimal. Low RAM or a VM selects lite; other machines default to balanced. Explicit visual overrides are supported. This is a conservative heuristic, not a benchmark.

Hardware classification uses PCI/USB vendor and class IDs and CPU/RAM information; matching firmware is installed only if the local APT candidate exists. Wi-Fi firmware selection is heuristic, not proof that a particular chipset is supported. If firmware packages are unavailable, review Debian non-free-firmware sources; the tool does not rewrite existing repository policy.

For a laptop with compatible NVIDIA hardware, add `--nvidia-driver` explicitly after reviewing the plan. It asks Debian nvidia-detect for the supported package, checks Secure Boot (defers if enabled/unknown), requires running-kernel headers and a no-removals APT simulation, then installs the Debian-recommended nvidia-driver. It does not install legacy branches automatically, disable Secure Boot, configure PRIME/Xorg or change GRUB. Reboot only after verifying DKMS. Intel/AMD/Mesa remains the tested Nix graphics wrapper; proprietary NVIDIA-only machines and render offload require real hardware testing. Do not assume a successful APT install proves Wayland compatibility.

## Full package ownership and gaps

- Required native packages: distro/apt/packages-base.txt and packages-full.txt. APT simulation precedes installation.
- Optional native packages: packages-full-optional.txt. APT candidates and no-removal simulation are checked; individual failures are warned.
- Flatpaks: apps-full.txt (required) and apps-full-optional.txt (attempted independently, unavailable IDs reported). Only installed profile apps are added to the live root settings; existing user choices remain.
- Original NixOS development, network diagnostics, gaming, multimedia, printing, virtualization and workstation app declarations were reviewed. Availability, versions, licenses and dependencies on Debian can differ.
- Cursor, Codex and Tailscale have an explicit post-bootstrap installer (`ryoku-workstation-tools`); remaining security tools (e.g. Burp/ZAP), phone webcam/v4l2loopback, database servers and personal configurations require separate review. No account credentials, VPN state, personal printer addresses or wallpapers are imported. No Docker/libvirt group membership or SSH server exposure is granted by Ryoku. Some Debian packages may start their normal system services at installation; review services and firewall before connecting to an untrusted network.
- Steam via Flatpak avoids enabling i386/non-free solely for Steam.
- Optional software failures do not mean Full parity: inspect WARN messages and compare actual installed apps.
- Full is much larger than Minimal. Do not run on the existing 24 GB VM without expanding the disk or making a separate test VM. No automatic partitioning.

## Acceptance gates

1. Backup NixOS and recovery USB; restore a sample backup file.
2. In a disposable Debian VM with adequate disk, test new Full installation and launch browser, editor, Settings, terminal, Flatpak apps. Check missing optional package warnings.
3. On actual laptop, verify PCI driver binding, kernel/DKMS, Mesa/Vulkan, NVIDIA PRIME on demand, Wi-Fi/Bluetooth/audio, display outputs, suspend/resume and power. Verify both Hyprland and Niri recovery.
4. Keep GDM initially. SDDM preview is validated separately; do not switch until the real greeter works.
5. Preserve the lockfile and local settings; edit source with Cursor, review diffs and push only redistributable code.

Status: source/fixture and CI tests are not real Full installation or bare-metal hardware certification.

## Personal migration (private checkout)

Before erasing NixOS, preserve the private source checkout or independently
verify you can restore it using another machine. In particular preserve
`assets/wallpapers/`, `hosts/notebook/drivers/4barcode/` and
`ryoku/settings.json`. Do not publish credentials, printer serials,
vendor driver binaries, or personal wallpapers in the public Ryoku repo.

On fresh Debian, install git, python3 and sudo using an administrator
account. Restore the private checkout to ~/ryoku-nixos (or adjust its path).
From the public Ryoku checkout, as the desktop user:

```sh
bash distro/scripts/ryoku-import-personal "$HOME/ryoku-nixos"
sudo bash distro/scripts/ryoku-bootstrap --apply --user "$USER" --profile full --hardware auto --visual auto --shell-style quattro --compositor hyprland
sudo bash distro/scripts/ryoku-printers "$HOME/ryoku-nixos"
bash distro/scripts/ryoku-workstation-tools
```

The personal import copies still images to
~/.local/share/ryoku/wallpapers-private, updates only the saved image
selections in the local root settings.json and queues a one-time DMS
wallpaper update. The existing Settings gallery displays both private and
public images. Private login wallpaper IDs are valid in the Debian semantic
hash; runtime SDDM helper validates access. GDM is unchanged; Apply does not
replace GDM or promise the SDDM login background.

Full installs CUPS, HPLIP/hpcups, Gutenprint, Epson ESC/P-R, Avahi and
system-config-printer. For the original 4BARCODE 4B-2054L driver 3.13.3,
ryoku-printers uses the **original private vendor filter** and PPD,
checks x86-64, cupstestppd and native library dependencies, and installs the
filter into Debian's CUPS filter directory. It does not download any
unlicensed binary. Plug in and power on the printers, then rerun the helper.
Single unambiguous matching USB devices can receive automatically configured
queues; HP Deskjet 1510 uses the HPLIP model and A4. Other connection types
or ambiguous matches require choosing the device in system-config-printer.
Do not reuse the old printer serial when the hardware differs. A successful
driver staging is not a physical print test: print an actual label and A4 page.

The optional post-bootstrap workstation installer uses the official
Cursor Debian download, npm @openai/codex in the desktop user's prefix,
and Tailscale's signed Trixie repository. It does not import credentials,
log into your accounts, or connect Tailscale automatically. Verify Cursor
launches, codex --version, and tailscale --version.

## Printers validation path (private drivers stay private)

Proprietary 4BARCODE filter/PPD files must never be committed to the public
tree. Validation on a Full host after personal import:

```sh
# From the public checkout, as root only with a trusted private path:
sudo bash distro/scripts/ryoku-printers "$HOME/ryoku-nixos"
lpstat -p -d
# Physical gate (NOT_TESTED from cloud agents): print one thermal label + one A4 page.
```

If queues were not auto-created (ambiguous USB matches), pick the model in
`system-config-printer`. Staging success ≠ print success.

## Sensors / Quattro monitor

```sh
bash distro/scripts/ryoku-hardware --sensors
```

Reports only readable `/proc`, hwmon, thermal_zone, power_supply and optional
UPower nodes. `nvidia-smi` runs once only if the proprietary stack is already
installed — it is not enabled as a continuous poller (hybrid dGPU stay asleep).

Bar GPU/VRAM widgets are **not** claimed yet: keep native CPU/RAM/temp via dgop;
watch any upstream dgop→dux-gop rename before swapping backends. See
`SERVICE_OWNERSHIP.md`, `VIDEO_WALLPAPER.md`, `FIREFOX_MEDIA.md`,
`NVIDIA_GDM_RECOVERY.md`, and `PERSONAL_VS_SHIPPED.md`.
