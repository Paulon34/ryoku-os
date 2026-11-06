# Ryoku OS

**Ryoku OS** é um sistema operacional Linux open source com foco em **OS + UX**: um núcleo estável (Linux upstream), componentes próprios em Rust (**Zaquion Core**), e uma experiência de desktop a portar (**Ryoku Desktop**).

> English: see [README.en.md](README.en.md).

## Visão

| Camada | Papel |
|--------|--------|
| **Kernel** | Linux upstream, sem modificações inicialmente; preparado para integrações futuras em Rust |
| **Zaquion Core** | Componentes, ferramentas e serviços de sistema em Rust (próprios) |
| **Ryoku Desktop** | GUI existente, projeto separado — a integrar/portar depois |
| **Compatibilidade** | Nix, Debian e Arch via integração e/ou isolamento |
| **Distribuição** | ISO + instalador (futuro); perfis Lite, Full, Gaming, Server |
| **Testes** | QEMU/KVM com automação progressiva |

## Por que este repositório?

Este monorepo (`ryoku-os`) concentra a fundação do sistema: documentação de arquitetura, espaço para Zaquion Core, embalagem futura e harness de testes. **Ryoku Desktop** e **ryoku-nixos** são projetos conceitualmente irmãos — preservados como referências externas; **não** são inventados nem copiados aqui.

## Estrutura (resumo)

```
ryoku-os/                 ← raiz deste repositório (/workspace)
├── zaquion-core/         # Rust: serviços e ferramentas próprias
├── kernel/               # Referência ao Linux upstream (não vendorado nesta fase)
├── apps/                 # Apps de usuários (Desktop fica fora, por enquanto)
├── compatibility/        # Nix / Debian / Arch
├── packaging/            # ISO, instalador, perfis
├── tests/                # Harness QEMU/KVM (futuro)
└── docs/                 # Arquitetura, ADRs, licensing, testes
```

Decisão de layout: [docs/architecture/layout.md](docs/architecture/layout.md) · ADR: [docs/architecture/ADR-0001.md](docs/architecture/ADR-0001.md)

## Estado atual (Missão 001)

- Fundação documental e estrutura lean do repositório
- Sem kernel baixado/compilado, sem ISO, sem VMs executadas
- Sem código de produção em Zaquion Core ainda

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [ROADMAP.md](ROADMAP.md) | Fases e próximos passos |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Como contribuir |
| [SECURITY.md](SECURITY.md) | Relato de vulnerabilidades |
| [docs/architecture/](docs/architecture/) | Visão e ADRs |
| [docs/testing/qemu-strategy.md](docs/testing/qemu-strategy.md) | Estratégia de testes QEMU |
| [docs/licensing/strategy.md](docs/licensing/strategy.md) | Estratégia de licenças |
| [docs/compatibility/](docs/compatibility/) | Nix / Debian / Arch |

## Idiomas

Documentação pública em **português** e **inglês**. O `README.md` principal está em português (audiência e nome do projeto). O espelho em inglês é `README.en.md`.

## Licenciamento

**Não** há uma única licença para todos os componentes. O kernel Linux impõe obrigações GPLv2; componentes próprios (Zaquion Core) e apps podem usar licenças distintas, desde que a compatibilidade seja documentada. Ver [docs/licensing/strategy.md](docs/licensing/strategy.md).

## Aviso

Este repositório está em fundação. Não use builds, ISOs ou imagens daqui como sistema de produção.

## Comunidade

- Issues e PRs via GitHub (quando o remoto público estiver publicado)
- Templates em [`.github/`](.github/)
