# Ryoku profiles (ENTREGA C)

## Axes

| Axis | Values | Default |
|------|--------|---------|
| Edition | `minimal`, `full` | `minimal` |
| Visual | `lite`, `balanced`, `ultra` | `balanced` |
| Shell style | `quattro`, `islands` | `quattro` |
| Jarvis | on/off | **off** (especially Minimal) |

## Bootstrap

```bash
./distro/scripts/ryoku-bootstrap --dry-run --user "$USER" \
  --profile minimal --visual balanced --shell-style quattro

sudo ./distro/scripts/ryoku-bootstrap --apply --user "$USER" \
  --profile full --visual ultra --shell-style islands --jarvis
```

Writes `distro/flake/.ryoku-user.nix` (gitignored) with the selected knobs.

## Module map

See `distro/flake/modules/README.md`.
