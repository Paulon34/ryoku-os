# Compositor selection (Debian Modular)

**Default after this port:** **Hyprland** (APT `trixie-backports` ~0.55.x).  
**Recovery:** **Niri** GDM session remains installed; do not uninstall from the VM until Hyprland is guest-proven.

## First Ryoku Hyprland guest login (Debian 0.55.x)

- `Ryoku (Hyprland)` uses `/usr/bin/start-hyprland` when available, for
  Hyprland crash recovery and safe mode. A legacy direct binary fallback
  exists for older guests.
- GDM `DesktopNames=Hyprland` and `XDG_CURRENT_DESKTOP=Hyprland` avoid the
  externally managed `Hyprland:Ryoku` warning while keeping the Ryoku session
  name.
- Install `hyprland-guiutils` from `trixie-backports` for graphical recovery
  dialogs (successor to the deprecated `hyprland-qtutils`).
- Hyprland 0.55.x requires window rules such as
  `windowrule = match:class ^(example)$, float on, center on`, not
  `windowrulev2 = float, class:^(example)# Compositor selection (Debian Modular)

**Default after this port:** **Hyprland** (APT `trixie-backports` ~0.55.x).  
 or
  `windowrule = float, class:^(example)# Compositor selection (Debian Modular)

**Default after this port:** **Hyprland** (APT `trixie-backports` ~0.55.x).  
.
- A red overlay after rebuilding may indicate the GDM session is still
  running the previous Home Manager generation. Log out normally and back in.
- `hyprctl configerrors` and `hyprctl layers` require a Hyprland session
  context: run them from Kitty **inside** that session, not from plain SSH.



## Matrix

| Choice | Default | Install | Session | Notes |
|--------|---------|---------|---------|-------|
| **Hyprland** | yes | APT backports `hyprland` + `xdg-desktop-portal-hyprland` | `Ryoku (Hyprland)` | Matches ryoku-desktop; Quattro workspace QML works |
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
# Hyprland
hyprctl layers
# Expect a Quickshell / dms:bar Top (or Overlay) surface when enabled=true

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
- Hyprland conf targets Debian **~0.55.x** (`windowrule = …` v2 semantics; no deprecated `windowrulev2`).
- Preserve guest `flake.lock` — no `nix flake update` on apply.
- Agent must not restart GDM/session/VM or delete Niri from the guest.
