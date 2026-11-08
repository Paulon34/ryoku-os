# Ryoku Debian (`distro/`)

Trilha **Debian Modular + Niri + Nix + Home Manager standalone + Jarvis (depois)**.

> Não continua o desktop Rust experimental (PRs `#6`–`#18`). Esses PRs permanecem abertos; sem merge/delete por esta trilha.

## ENTREGA A — Fundação VM Debian 13

Alvo: Debian 13 Trixie amd64 utilizável com APT + Nix multiusuário (`nix-setup-systemd`) + HM standalone + Niri + sessão Wayland (GDM) + Kitty + Thunar + Fuzzel + NetworkManager + PipeWire + portals + polkit + XWayland + Mesa (+ nixGL para apps Nix).

### Comandos na VM Debian

```bash
# 1) Clone
git clone https://github.com/Paulon34/ryoku-os.git
cd ryoku-os

# 2) Pré-visualizar (não escreve nada durable)
./distro/scripts/ryoku-bootstrap --dry-run --user "$USER"

# 3) Aplicar (pede confirmação APPLY; use --yes em automação revisada)
sudo ./distro/scripts/ryoku-bootstrap --apply --user "$USER"

# 4) Logout → GDM → sessão "Ryoku (Niri)"
```

### Testes automáticos (host CI / sem guest)

```bash
./distro/tests/test-distro-paths.sh
./distro/tests/test-bootstrap-policy.sh
```

### Status de verificação

| Checagem | Status |
|----------|--------|
| Testes de path/policy | devem passar no CI |
| Guest Debian + login Niri | **`GUEST_NOT_RUN`** até evidência manual |
| `PASS_MANUAL` | **não inventar** |

## Documentação

- [Arquitetura](docs/RYOKU_DEBIAN_ARCHITECTURE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Hyprland → Niri keybinds](../docs/migration/HYPRLAND_TO_NIRI_KEYBINDS.md)

## Próximas entregas

| Entrega | Conteúdo |
|---------|----------|
| B | Port visual ryoku-desktop → Niri/DMS (patches 1.5.3, Matugen, wallpapers) |
| C | Perfis Lite/Balanced/Ultra + Minimal/Full |
| D | ryoku-cli / Jarvis bridge (Rust; off no Minimal) |
| E | ISO live-build + Calamares (só após desktop ok) |

## Segurança do bootstrap

- Recusa NixOS
- Sem GRUB / partições / EFI
- Backup + logs + `RECOVERY.md`
- Sem auto-run no host do desenvolvedor
