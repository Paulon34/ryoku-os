# Compatibilidade — Nix, Debian, Arch

## Objetivo

Permitir que o Ryoku OS **integre** ou **isole** ecossistemas existentes sem fingir um único gerenciador de pacotes universal na fundação.

## Abordagens

| Modo | Ideia | Quando usar |
|------|-------|-------------|
| **Integração** | Camada Ryoku/Zaquion consome pacotes do ecossistema hospedeiro | Usuário já tem Debian/Arch/Nix e quer serviços Zaquion |
| **Isolamento** | Container, nix-shell, chroot, ou imagem de perfil dedicada | Evitar conflitos de libc/ABI; perfis Server/Gaming |
| **Imagem de perfil** | Rootfs construído a partir de um bootstrap escolhido | ISO Ryoku futura |

## Pastas

- `compatibility/nix/` — flakes, overlays, notas (sem inventar ryoku-nixos completo)
- `compatibility/debian/` — packaging `.deb`, apt notes
- `compatibility/arch/` — PKGBUILD notes

**ryoku-nixos** (se existir como projeto irmão) permanece externo; aqui só há âncoras e documentação.

## Decisões adiadas (ADR futuro)

- Qual bootstrap é o default da ISO (Debian, Arch, NixOS-based, ou multi-profile).
- Como Desktop consome toolkits de cada ecossistema.
- Política exacta de “Nix on Debian host” vs “Debian in Nix”.

## Missão 001

Apenas estrutura e intenções. Nenhum pacote gerado.
