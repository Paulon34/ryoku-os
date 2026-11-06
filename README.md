# Ryoku OS

**Ryoku OS** é um sistema operacional Linux open source **em desenvolvimento** (fundação), com foco em **OS + UX**: núcleo Linux upstream, componentes próprios em Rust (**Zaquion Core**), e uma experiência de desktop a portar (**Ryoku Desktop**).

> English: see [README.en.md](README.en.md).

**Aviso de produto:** ainda **não** há ISO funcional, instalador completo, nem imagem bootável Ryoku para uso diário. Este repositório publica a fundação (docs, Zaquion tooling, Virtual Lab). Não trate o conteúdo como distro pronta.

## Visão

| Camada | Papel |
|--------|--------|
| **Kernel** | Linux upstream, sem modificações inicialmente; preparado para integrações futuras em Rust |
| **Zaquion Core** | Componentes, ferramentas e serviços de sistema em Rust (próprios) |
| **Ryoku Desktop** | GUI existente, projeto separado — a integrar/portar depois |
| **Compatibilidade** | Nix, Debian e Arch via integração e/ou isolamento |
| **Userland base** | **Ainda não formalizado** — Debian / Arch / Nix (ou multi-perfil) fica para ADR futuro; não presumir um bootstrap único |
| **Distribuição** | ISO + instalador (**futuro**); perfis Lite, Full, Gaming, Server |
| **Testes** | QEMU/KVM com automação progressiva (Virtual Lab T0/T1) |

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
├── tests/qemu/           # Virtual Lab (T0/T1 harness assets)
└── docs/                 # Arquitetura, ADRs, licensing, testes
```

Decisão de layout: [docs/architecture/layout.md](docs/architecture/layout.md) · ADR: [docs/architecture/ADR-0001.md](docs/architecture/ADR-0001.md)

## Estado atual

- Fundação documental + Zaquion (`ryoku-doctor`) + **Virtual Lab** (`ryoku-virtlab` T0/T1)
- T1 **SKIPPED** sem QEMU no host típico; **sem** claim de boot Ryoku; **sem** ISO/kernel baixados neste repo
- Repositório público previsto: [github.com/Paulon34/ryoku-os](https://github.com/Paulon34/ryoku-os)

### Zaquion / Virtual Lab

```bash
cd zaquion-core
cargo test --workspace
cargo run -p ryoku-doctor
cargo run -p ryoku-virtlab -- all
```

Ver [zaquion-core/README.md](zaquion-core/README.md) e [docs/testing/virtual-lab.md](docs/testing/virtual-lab.md).

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [ROADMAP.md](ROADMAP.md) | Fases e próximos passos |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Como contribuir |
| [SECURITY.md](SECURITY.md) | Relato de vulnerabilidades |
| [docs/architecture/](docs/architecture/) | Visão e ADRs |
| [docs/testing/qemu-strategy.md](docs/testing/qemu-strategy.md) | Estratégia de testes QEMU |
| [docs/licensing/strategy.md](docs/licensing/strategy.md) | Estratégia de licenças |
| [docs/performance/targets.md](docs/performance/targets.md) | Metas de performance (preliminares) |
| [docs/compatibility/](docs/compatibility/) | Nix / Debian / Arch |
| [zaquion-core/README.md](zaquion-core/README.md) | Workspace Rust / MSRV / comandos |

## Idiomas

Documentação pública em **português** e **inglês**. O `README.md` principal está em português (audiência e nome do projeto). O espelho em inglês é `README.en.md`.

## Licenciamento

**Não** há uma única licença para todos os componentes. O kernel Linux impõe obrigações GPLv2; componentes próprios (Zaquion Core) e apps podem usar licenças distintas, desde que a compatibilidade seja documentada. Ver [docs/licensing/strategy.md](docs/licensing/strategy.md).

## Aviso

Este repositório está em fundação. Não use builds, ISOs ou imagens daqui como sistema de produção.

## Comunidade

- Issues e PRs: [Paulon34/ryoku-os](https://github.com/Paulon34/ryoku-os)
- Templates em [`.github/`](.github/)
- Relato de segurança: ver [SECURITY.md](SECURITY.md)
