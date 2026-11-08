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

# 2) Pré-visualizar / preflight (não escreve nada durable)
./distro/scripts/ryoku-bootstrap --dry-run --user "$USER"

# 3) Aplicar (pede confirmação APPLY; use --yes em automação revisada)
#    Escreve distro/flake/hosts/$USER/default.nix, faz git add, e
#    roda home-manager switch --flake …#$USER **como esse usuário**.
sudo ./distro/scripts/ryoku-bootstrap --apply --user "$USER"

# 4) Logout → GDM → sessão "Ryoku (Niri)"
```

### Aprendizados do primeiro teste real (Debian 13 no Proxmox)

O primeiro bootstrap encontrou problemas **reproduzidos na VM**, e a fundação
passou a tratá-los automaticamente:

- **APT:** `policykit-1` não existe no Debian 13; usar `polkitd` + `pkexec`.
- **Nix daemon:** se `nix-daemon.service` já estiver ativo, não tentar ativar
  `nix-daemon.socket` ao mesmo tempo. Autorizar o usuário de desktop no grupo
  `nix-users` (nova sessão SSH para atualizar os grupos).
- **GDM:** o alias `gdm.service` é estático; conferir `display-manager.service`
  e selecionar `graphical.target` para a próxima inicialização quando o
  alvo anterior for `multi-user.target`. Não iniciar a GUI durante o SSH.
- **PipeWire:** `systemctl --user` requer sessão e barramento D-Bus do usuário.
  Deixar a ativação dos serviços de áudio para o login da sessão gráfica.
- **Home Manager:** criar `distro/flake/hosts/<user>` como usuário de desktop,
  nunca como root seguido de `tee` sob um usuário sem permissão.
- **nixGL:** usar o wrapper Mesa (`nixGLIntel`) na flake pura. O antigo
  `nixGLDefault` tenta usar `builtins.currentTime` ao detectar NVIDIA e
  bloqueia a avaliação pura do Home Manager.

A VM de laboratório tem 25 GiB de disco virtual; acompanhar `df -h /`
durante a ativação das gerações do Nix. Nenhum desses testes significa
que o login Niri já foi verificado.

Se uma tentativa antiga parou após APT/Nix e foi atualizado o checkout
para uma versão corrigida da mesma branch, é possível retomar sem
reinstalar os pacotes:

```bash
sudo ./distro/scripts/ryoku-bootstrap --apply --user "$USER" \
  --skip-apt --skip-nix --profile minimal --visual balanced --shell-style quattro
```

Para instalações limpas, **não** usar esses `--skip-*`.

### Testes automáticos (host CI / sem guest)

```bash
./distro/tests/test-distro-paths.sh
./distro/tests/test-bootstrap-policy.sh
bash ./distro/tests/test-debian13-regressions.sh
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
| B | Port visual ryoku-desktop → Niri/DMS |
| C | Perfis Lite/Balanced/Ultra + Minimal/Full |
| D | ryoku-cli / Jarvis bridge (Rust; off no Minimal) |
| E | ISO live-build + Calamares (só após desktop ok) |

## Segurança do bootstrap

- Recusa NixOS
- Sem GRUB / partições / EFI
- Backup + logs + `RECOVERY.md`
- Sem auto-run no host do desenvolvedor
