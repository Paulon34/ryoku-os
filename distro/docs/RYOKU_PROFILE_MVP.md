# Ryoku Profile — MVP architecture (design only)

**Scope now:** documentation + contract. **Not** a full GUI, Git marketplace, or exact machine clone.

Test-order position: **A Desktop** (current) → B Apps → **C Modular (this)** → D Git profiles → E real migration.

## Goal

A declarative **profile manifesto** that can be dry-run and applied idempotently on Debian Modular, reusing:

- `distro/scripts/ryoku-bootstrap` (APT / GDM / Nix / HM host)
- `distro/flake` Home Manager (`ryoku.profile.*`, DMS, Niri, Matugen)
- existing wallpapers / patches / session wrappers

## Manifest (YAML) — proposed shape

```yaml
# Example only — no secrets, tokens, or PII.
schemaVersion: 1
id: paulo-desktop-quattro
name: Paulo desktop Quattro
edition: minimal          # maps to ryoku.profile.edition
visual: balanced          # ryoku.profile.visual
shellStyle: islands       # ryoku.profile.shellStyle (quattro selectable)
compositor: hyprland      # default; niri = GDM recovery session
jarvis: false

modules:
  desktop.niri: true
  desktop.dms: true
  desktop.matugen: true
  apps.kitty: true
  apps.thunar: true

apt:
  - network-manager-gnome
  - mate-polkit

flatpak: []               # ids only, e.g. org.mozilla.firefox

# Trusted external .deb — metadata only, never binary blobs in git
externalDebs: []
# - source: https://example.invalid/repo
#   id: example-app
#   version: "1.2.3"
#   sha256: "..."

prefs:
  export:
    - DankMaterialShell/settings.json   # allowlist paths under ~/.config
  # restore is explicit + reviewed; never silent overwrite of secrets files

themes:
  wallpaper: ryoku-night.jpg
  fonts:
    mono: JetBrainsMono Nerd Font
```

## Apply contract

| Mode | Behavior |
|------|----------|
| `dry-run` | Resolve manifesto → print APT/Flatpak/HM/module plan; write nothing durable |
| `apply` | Idempotent: install missing pkgs, enable modules, HM switch; skip unchanged |
| `export-prefs` | Copy allowlisted prefs into a profile bundle (no tokens/keyrings) |
| `restore-prefs` | Preview diff → apply only after confirmation |

**Error recovery:** leave previous HM generation + bootstrap `RECOVERY.md`; never wipe `$HOME`.

**Reproducibility:** best-effort package sets + pinned flake inputs — **not** bit-identical disk clones.

## What already exists (reuse)

| Piece | Location |
|-------|----------|
| Profile knobs | `distro/flake/modules/profiles.nix` |
| Host attr | `distro/flake/hosts/<user>/default.nix` |
| Bootstrap flags | `--profile --visual --shell-style --jarvis` |
| Desktop modules | `distro/flake/home/{niri,dms,matugen,theme,kitty}.nix` |

## What to build later (ordered slices)

1. **MVP slice (next after desktop PASS):** `profile.manifest.yaml` schema validator + `ryoku-profile dry-run` wrapping bootstrap plan output  
2. Module enable map → which HM imports / APT extras activate  
3. Prefs export allowlist + restore dry-run  
4. Flatpak id list apply  
5. External .deb metadata fetch/verify (sha256) — still no blobs in git  
6. “Detect new apps” suggestion list (manual include) — post-MVP  
7. GUI — only after CLI dry-run/apply is trusted  

## Non-goals (now)

- Shipping ISO / Calamares  
- Replacing Nix/HM wholesale  
- Syncing secrets from NixOS  
- Claiming exact reproducibility across machines  
