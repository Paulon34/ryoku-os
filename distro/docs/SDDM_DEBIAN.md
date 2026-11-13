# Ryoku SDDM Astronaut — Debian 13 (opt-in)

This ports the original Ryoku NixOS Astronaut *visual overlay* to the Debian
SDDM Qt6 greeter. It keeps SDDM's upstream auth, session selection and
shutdown actions. It is **not** a lock screen and does not replace the DMS
screen locker.

## Status and safety

The Debian Minimal bootstrap currently uses **GDM**. Do **not** remove it.
Only use this opt-in port on a VM snapshot first. The theme is staged before
the display manager is switched, and the switch takes effect on the **next
boot** only. Both Ryoku Hyprland and Ryoku Niri recovery desktop sessions
remain installed in `/usr/share/wayland-sessions`.

The source QML overlays are adapted from the private Ryoku project, with
upstream Keyitdev/MarianArlt GPLv3+ notices retained. Only the three
redistributable overlay files are published. Private wallpapers and user
settings are never copied into Git. The installer fetches Astronaut upstream
at pinned commit `abb3163c724935af888ba5ea9ac0c4f22afd8048` **without
running the upstream setup script**.

## Worktree and Home Manager on the existing Proxmox VM

PR #32 is stacked on #31. Do **not** run a fresh Minimal/Full package
bootstrap or reset the #31 worktree. Prepare a separate checkout so the
working Islands desktop stays recoverable:

```sh
cd ~/ryoku-os-apps-31
git fetch origin refs/heads/cursor/debian-sddm-ryoku:refs/remotes/origin/cursor/debian-sddm-ryoku
git worktree add --detach ~/ryoku-os-sddm-32 origin/cursor/debian-sddm-ryoku
cp ~/ryoku-os-apps-31/distro/flake/flake.lock ~/ryoku-os-sddm-32/distro/flake/flake.lock
mkdir -p ~/ryoku-os-sddm-32/distro/flake/hosts/paulo
cp ~/ryoku-os-apps-31/distro/flake/hosts/paulo/default.nix ~/ryoku-os-sddm-32/distro/flake/hosts/paulo/default.nix
sed -i 's#/home/paulo/ryoku-os-apps-31#/home/paulo/ryoku-os-sddm-32#g' ~/ryoku-os-sddm-32/distro/flake/hosts/paulo/default.nix
cd ~/ryoku-os-sddm-32
git add -f distro/flake/flake.lock
git add distro/flake/hosts/paulo/default.nix
bash distro/tests/test-sddm-port.sh
nix --extra-experimental-features "nix-command flakes" build --no-link './distro/flake#homeConfigurations.paulo.activationPackage'
```

If the Nix build succeeds, activate the **new Ryoku Settings binary** and
other HM files without reinstalling APT, Flatpak or Nix:

```sh
sudo ./distro/scripts/ryoku-bootstrap --apply --user paulo --profile minimal \
  --visual balanced --shell-style islands --compositor hyprland \
  --skip-apt --skip-flatpak --skip-nix
```

Keep the existing GUI session and do not restart GDM yet. Close and reopen
Ryoku Settings after HM activation, then continue with the staged theme.

## VM procedure — preserve the last working GDM snapshot

SSH to Debian VM 201 and use the SDDM PR worktree. On Debian 13, install
Qt6 runtime imports rather than using a Nix-built greeter against Debian
graphics drivers.

Before APT, confirm a Proxmox snapshot exists. Prevent the Debian
display-manager debconf prompt from selecting SDDM prematurely:

```sh
printf '%s\n' \
  'gdm3 shared/default-x-display-manager select gdm3' \
  'sddm shared/default-x-display-manager select gdm3' \
  | sudo debconf-set-selections

sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  sddm qml6-module-qtquick qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-effects \
  qml6-module-qtquick-window qml6-module-qtquick-virtualkeyboard \
  qml6-module-qtmultimedia qt6-svg-plugins imagemagick \
  libxcb-cursor0 file git python3
```

Check the active login manager before proceeding:

```sh
systemctl status display-manager.service --no-pager
readlink -f /etc/systemd/system/display-manager.service
```

APT may change the display-manager selection during package configuration.
If it did, restore GDM before reboot via Debian's
`sudo dpkg-reconfigure gdm3` or the Proxmox console; do not reboot into an
unpreviewed greeter. The theme installer below does **not** stop either
display-manager service.

From the PR worktree:

```sh
sudo bash distro/scripts/ryoku-sddm stage paulo
bash distro/scripts/ryoku-sddm status
bash distro/scripts/ryoku-sddm preview
```

Preview renders inside the current graphical session. Confirm username,
password (test-mode cannot authenticate), Ryoku visual layout, clock, mouse,
session selector with Hyprland and Niri, and the current login wallpaper.

Only after a working greeter preview and a snapshot:

```sh
sudo bash distro/scripts/ryoku-sddm activate
```

Type `SWITCH` when prompted. It updates `display-manager.service` only for
the next boot. It does **not** restart the live desktop.

Then reboot from the Proxmox UI, see Ryoku SDDM, and log into
`Ryoku (Hyprland)`. Also verify `Ryoku (Niri recovery)` remains selectable.

## Login wallpaper from Ryoku Settings

`Ryoku Settings → Aparência → Tela de login` is **separate** from the
desktop wallpaper picker. Choose an image and **Salvar**. On Debian with
staged SDDM, Settings calls `pkexec` with one image **basename**. The
dedicated helper `/usr/local/libexec/ryoku-sddm-wallpaper` verifies the
caller via `PKEXEC_UID`, limits the source to Ryoku's public or locally
imported private gallery, converts an image into
`/usr/share/sddm/themes/ryoku-astronaut/Backgrounds/ryoku-current.png`,
and installs it root-owned/world-readable. This avoids depending on SDDM's
system user being able to traverse a private `/home` directory. The new
background becomes visible on the next greeter presentation.

The helper is deliberately not allowed to run arbitrary shell commands,
change the active display manager, or read arbitrary home paths. If SDDM
is not yet staged, Settings still saves the choice in
`ryoku/settings.json`, and the staging script imports the saved value.
No image data from `wallpapers-private` is ever committed to Git.

## Recovery

The installer saves the previous display-manager unit and executable in
`/var/lib/ryoku/sddm/`. If SDDM fails after switching, SSH into the VM
or use a Proxmox TTY and run from the worktree:

```sh
sudo bash distro/scripts/ryoku-sddm rollback
sudo reboot
```

Rollback restores the display-manager selection for the **next boot**
without removing the original GDM package, Niri recovery session or
wallpapers. If display-manager state was changed during the preliminary
APT install, resolve that separately before activation.

## Validation status

Source/static checks can verify file paths, permissions policy, QML
dependencies and Bash syntax, but cannot prove the greeter renders or logs
in. **No PASS_GUEST_SDDM claim until the Debian VM actually previews and
boots into the greeter**. Testing Intel/NVIDIA hardware on the notebook is
a separate validation gate.
