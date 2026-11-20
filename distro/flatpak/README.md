# Ryoku Flatpak manifests (Debian Modular)

| File | Profile | Role |
|------|---------|------|
| `apps-minimal.txt` | `minimal` | No apps by default; Flathub remote still ensured |
| `apps-full.txt` | `full` | Flatseal, LocalSend, Telegram (Flathub, x86_64) |

## Rules

- IDs only (reverse-DNS). No nix-flatpak / NixOS dependency.
- Bootstrap (`ryoku-bootstrap`) and `ryoku-flatpak-sync` install idempotently:
  skip already installed; fail honestly on network/remote errors.
- Source of truth for Settings GUI: `apps.flatpakDeclared` in `ryoku/settings.json`.
  Full-profile bootstrap merges `apps-full.txt` into that list.
- APT owns Firefox ESR, Kitty, Thunar, GIMP, VLC/MPV, LibreOffice, etc.
  Flatpak owns the IDs listed here — do not duplicate the same app on both
  stacks in the default profiles.

## Validate an ID

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://flathub.org/api/v2/appstream/<id>"
# expect 200
```
