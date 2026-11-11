# Compositor selection (Debian Modular)

**Default after this port:** **Hyprland** (APT `trixie-backports` ~0.55.2).  
**Recovery:** **Niri** GDM session remains installed; do not uninstall from the VM until Hyprland is guest-proven.

## First Ryoku Hyprland guest login (Debian 0.55.2)

- `Ryoku (Hyprland)` uses `/usr/bin/start-hyprland` when available, for
  Hyprland crash recovery and safe mode. A legacy direct binary fallback
  exists for older guests.
- GDM display name stays **Ryoku (Hyprland)**. `DesktopNames=Hyprland` and
  `XDG_CURRENT_DESKTOP=Hyprland` (not `Hyprland:Ryoku`) keep portals/Qt/GTK
  and DMS happy.
- Install `hyprland-guiutils` from `trixie-backports` for graphical recovery
  dialogs (successor to the deprecated `hyprland-qtutils`).
- Hyprland **0.55.2** window/layer rules (verified from upstream
  `ConfigManager::handleWindowrule` / `handleLayerrule`):

  ```
  windowrule = match:class ^(example)$, float on, center on
  layerrule = match:namespace ^(dms:.*)$, no_anim on
  ```

  Not valid on 0.55.2 (startup overlay / `configerrors`):

  - `windowrulev2 = …` (hard deprecation)
  - `windowrule = float, class:^(example)$` → `invalid field float: missing a value`
  - `layerrule = noanim, ^(dms:.*)$` → bare effect / missing `match:namespace`

- A red overlay after rebuilding may indicate the GDM session is still
  running the previous Home Manager generation. Log out normally and back in
  (agent must not restart GDM/VM).
- `hyprctl configerrors` and `hyprctl layers` require a Hyprland session
  context: run them from Kitty **inside** that session, not from plain SSH.

## Matrix

| Choice | Default | Install | Session | Notes |
|--------|---------|---------|---------|-------|
| **Hyprland** | yes | APT backports `hyprland` + `xdg-desktop-portal-hyprland` + `hyprland-guiutils` | `Ryoku (Hyprland)` | Matches ryoku-desktop; Quattro workspace QML works |
| Niri | recovery | Nix HM package + nixGL | `Ryoku (Niri)` | Keep selectable via `--compositor niri` |

## Profile knob

```nix
# hosts/<user>/default.nix
profile.compositor = "hyprland"; # or "niri"
profile.shellStyle = "islands";  # test visual; "quattro" selectable
```

Bootstrap:

```bash
sudo ./distro/scripts/ryoku-bootstrap --apply --user "$USER" \
  --profile minimal --visual balanced --shell-style islands --compositor hyprland
```

## Proof of bar surface

Prefer compositor layers over IPC-only `visible`:

```bash
# Hyprland (inside the session)
hyprctl configerrors   # expect empty
hyprctl layers         # expect Quickshell / dms:bar Top (or Overlay)
# Niri recovery
NIRI_SOCKET=$(find /run/user/$(id -u) -maxdepth 1 -type s -name 'niri.*.sock' -print -quit)
NIRI_SOCKET="$NIRI_SOCKET" niri msg layers
```

## Safety

- **Session-scoped:** only the GDM-chosen session starts a compositor. Hyprland
  `exec-once` never launches Niri; Niri never starts under a Hyprland login.
- **Recovery under `compositor=hyprland`:** HM always installs Niri binary,
  `nixGLIntel`, `~/.config/niri/config.kdl`, and `ryoku-niri-session`.
- Bootstrap installs **both** GDM `.desktop` files; APT Hyprland failure **aborts**.
- Hyprland conf targets Debian **~0.55.2** (`match:*` + valued effects; no
  deprecated `windowrulev2`; no bare `float,` / `noanim,`).
- Preserve guest `flake.lock` — no `nix flake update` on apply.
- Agent must not restart GDM/session/VM or delete Niri from the guest.
- HM switch uses Debian `dbus-run-session` as the desktop user; do not restart
  live `systemd --user` units from bootstrap without explicit auth.
