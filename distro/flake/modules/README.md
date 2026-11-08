# Shared modules (ENTREGA C)

| Module | Role |
|--------|------|
| `profiles.nix` | Options: `edition` (minimal/full), `visual` (lite/balanced/ultra), `shellStyle`, `jarvis` |
| `features/minimal.nix` | Minimal edition — Jarvis off by default |
| `features/full.nix` | Full edition extras |
| `features/visual.nix` | Writes `~/.config/ryoku/profile.json` budget hints |

Imported from `home/home.nix` via `../modules`.
