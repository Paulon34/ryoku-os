# Compositor selection (Debian Modular)

**Status:** recommendation + option stub only. **No Hyprland migration in this track.**

## Default

| Choice | Default | Why now |
|--------|---------|---------|
| **Niri** | yes | Already proven on VM 201 (GDM session, keybinds, Kitty/Thunar, HM, validate, DMS shell.qml load). Matches Entrega A/B stack. |
| Hyprland | future | Native home of Ryoku Desktop Quattro patches (custom workspace QML uses `Hyprland.*`). Better visual parity for Quattro workspace strip, but would reopen session/GBM/portal validation on Debian. |

## Recommendation

1. **Stabilize Quattro on Niri first** (current priority). Treat stock DMS workspaceSwitcher on Niri as an accepted Hyprland→Niri limit.
2. When Quattro bar/wallpaper/menus are guest-proven, add a selectable `ryoku.profile.compositor` implementation:
   - shared DMS/Matugen/theme modules
   - compositor-specific session wrapper + binds + Matugen template
   - fail-closed HM assertion until the Hyprland path is wired (already in `profiles.nix`)
3. Keep rollback: foundation worktree + previous HM generation; never dual-default both compositors in one GDM session without an explicit host knob.

## Evidence (current stack)

- Niri: guest-proven foundation (session up, binds, apps).
- Quattro custom workspaces: patch gated on `CompositorService.isHyprland` → N/A on Niri.
- Hyprland on Debian Modular: **not implemented** (no session desktop, no HM module).

## Option

```nix
# hosts/<user>/default.nix — only "niri" evaluates today
profile.compositor = "niri";
```
