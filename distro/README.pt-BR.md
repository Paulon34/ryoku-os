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
- **dconf + D-Bus:** o primeiro `home-manager switch` da VM compilou a
  geração, mas falhou na ativação `dconfSettings` porque o dbus-daemon da
  Nix store procurou `/etc/dbus-1/session.conf` (o Debian 13 usa
  `/usr/share/dbus-1/session.conf`). O bootstrap agora chama
  `/usr/bin/dbus-run-session -- nix ...` **como usuário de desktop**.
  Isso fornece `DBUS_SESSION_BUS_ADDRESS` ao Home Manager sem alterar
  a configuração global do D-Bus.
- **Primeiro login GDM / Niri 26.04:** o GDM autenticou e iniciou Niri,
  mas o compositor rejeitou o KDL em `config.kdl:35`:
  `unexpected node prefers-no-csd`. Corrigido para `prefer-no-csd`;
  o bootstrap passa a executar `niri validate` como usuário após o
  Home Manager para barrar novos erros antes do login gráfico.
- **GBM / Mesa no Debian:** o mesmo boot mostrou
  `/run/opengl-driver/lib/gbm/dri_gbm.so` ausente. Esse caminho
  pertence ao ambiente NixOS, não ao Debian; o lançador
  `ryoku-niri-session` agora invoca o Niri do Nix via `nixGLIntel`
  para configurar o caminho de drivers Mesa. Isso ainda precisa de
  reteste real, pois o adaptador da VM era Bochs VGA (`1234:1111`).
  O Niri recomenda aceleração 3D para VMs; configurar a GPU virtual
  no hipervisor depois de preservar o acesso SSH e um snapshot.

A VM de laboratório tem 25 GiB de disco virtual; acompanhar `df -h /`
durante a ativação das gerações do Nix. A fundação Niri + Kitty já foi
verificada manualmente na VM Proxmox 201 (monitor virtual e janela no IPC).
Isso NÃO valida DMS, Quattro, widgets nem paridade visual com o NixOS.

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
| Guest Debian + Niri/Kitty | **`PASS_MANUAL` limitado** (compositor, monitor e Kitty) |
| DMS/Quattro/Matugen no guest | **`GUEST_NOT_RUN`** até teste visual real |
| Home Manager pure eval + build DMS 1.5.3 Quattro | **PASS CI** (não equivale a GUI verificada) |

## Documentação

- [Arquitetura](docs/RYOKU_DEBIAN_ARCHITECTURE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Hyprland → Niri keybinds](../docs/migration/HYPRLAND_TO_NIRI_KEYBINDS.md)

## ENTREGA B — shell Ryoku (Quattro / Islands)

Esta branch integra o trabalho visual do PR #20 sobre a fundação validada no
Proxmox: DMS 1.5.3 com patches Ryoku, wallpapers, Matugen e atalhos Niri.
O build de `.#dms-shell-ryoku` e a avaliação pura do Home Manager passaram no
GitHub Actions; ainda é necessário testar a UI na VM. Siga
[distro/docs/RYOKU_DMS_VM_TEST.md](docs/RYOKU_DMS_VM_TEST.md) para usar
um worktree isolado e ter um rollback seguro.
A instalação da fundação (GDM/Niri/Kitty) teve verificação manual positiva,
mas o DMS/Quattro, wallpaper, launcher e os serviços de sessão ainda devem
ser verificados dentro da VM antes de marcar a Entrega B como aprovada.

O Niri 26.04 aceita `include optional=true "colors.kdl"` e exige
`prefer-no-csd` (não `prefers-no-csd`). O bootstrap valida o KDL após
a ativação do Home Manager. Para testes com Proxmox, usar GPU virtual com
renderização disponível e conferir o console/SSH antes de novas mudanças.

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
