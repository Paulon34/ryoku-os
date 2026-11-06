# Roadmap — Ryoku OS

Documento vivo. Atualizar a cada missão concluída. Idiomas: seções principais em português; termos técnicos em inglês quando padrão da indústria.

## Princípios de progresso

1. **Kernel intacto primeiro** — Linux upstream sem patches próprios até haver necessidade clara e processo de manutenção.
2. **Zaquion Core incremental** — serviços Rust pequenos, testáveis, com contratos estáveis.
3. **Testes antes de ISO** — QEMU/KVM automatizado precede distribuição pública de imagens.
4. **Compatibilidade sem forçar união** — Nix / Debian / Arch por integração ou isolamento, não por “um meta-distro” prematuro.
5. **Desktop separado** — Ryoku Desktop permanece projeto irmão até uma missão de port dedicada.

---

## Fase 0 — Fundação (Missão 001) ✅ em curso / entregue nesta missão

- [x] Inspeção do ambiente de desenvolvimento (somente leitura)
- [x] Estrutura lean do monorepo `ryoku-os`
- [x] README PT/EN, ROADMAP, CONTRIBUTING, SECURITY
- [x] ADR-0001 e docs de arquitetura
- [x] Estratégia de testes QEMU (documentada, não executada)
- [x] Estratégia de licensing (documentada)
- [x] Templates GitHub e `.gitignore`
- [ ] Revisão humana / publicação do remoto público

## Fase 1 — Bootstrap de ferramenta e CI documental (Missão 002) ✅ entregue nesta missão

- [x] Workspace Cargo em `zaquion-core/` com crate `ryoku-doctor`
- [x] Doctor read-only (Rust/Clang/QEMU/KVM/…) com testes injetáveis — sem instalar pacotes
- [x] CI GitHub Actions: `cargo fmt` / `check` / `test` / `clippy` + checagem de paths de docs
- [x] Dual MIT OR Apache-2.0 em Zaquion Core; MSRV 1.75 / pin 1.83.0
- [x] Metas preliminares de performance (`docs/performance/targets.md`) — goals ≠ measured
- [ ] Política de submódulos / referência ao tree do kernel (pin de versão, sem vendorar fonte completa se evitável)
- [ ] Link-check Markdown completo (além da existência de paths)

## Fase 2 — Harness QEMU — T0/T1 (003) + First Boot Lab (005)

- [x] Virtual Lab + `ryoku-virtlab` T0 (validação sem QEMU)
- [x] T1 opcional: SKIPPED sem QEMU; sem claim de boot Ryoku
- [x] Doctor: QEMU / qemu-img / KVM / TCG
- [x] Manifesto Alpine virt 3.21.9 + script fetch **dry-run** + first-boot harness (Missão 005)
- [x] Workflow `first-boot.yml` **gated** (`if: false`) — sem download/install até review
- [ ] Disponibilizar QEMU no host/CI **com autorização**
- [ ] `RYOKU_FETCH_EXECUTE=1` + first-boot PASS com logs seriais verificáveis (ainda ≠ Ryoku)
- [ ] Smoke: boot → login/ssh → shutdown em imagem autorizada
- [ ] Artefatos de expectativa extras (texto pequeno no git)

Ver [docs/testing/reference-linux.md](docs/testing/reference-linux.md), [virtual-lab.md](docs/testing/virtual-lab.md).

## Fase 3 — Primeiros serviços Zaquion Core

- [ ] Definição de IPC/API inicial (ex.: socket + schema versionado)
- [ ] Serviço piloto (ex.: inventário de hardware read-only ou healthd)
- [ ] Empacotamento experimental (deb e/ou nix flake) em `compatibility/`
- [ ] Testes unitários + integração no QEMU

## Fase 4 — Empacotamento e perfis

- [ ] Esboço do instalador (texto primeiro; GUI depois)
- [ ] Perfis: Lite, Full, Gaming, Server (conteúdo mínimo por perfil)
- [ ] Pipeline de ISO *reproduzível* (meta; ferramentas a escolher — ver ADR futuro)
- [ ] Testes: instalador → reboot → smoke gráfico (quando Desktop existir no tree)

## Fase 5 — Ryoku Desktop (port)

- [ ] Inventário do repositório/projeto Ryoku Desktop existente
- [ ] Estratégia de integração (submódulo, subtree, ou consumo de pacote)
- [ ] Sessão gráfica em QEMU (virtio-gpu / spice) automatizada de forma progressiva

## Fase 6 — Kernel e Rust no kernel (longo prazo)

- [ ] Avaliar rust-for-linux / módulos out-of-tree
- [ ] Processo de patch e rebase contra LTS
- [ ] Nunca misturar código proprietário no tree GPLv2 do kernel

## Fora de escopo (explícito)

- Fork agressivo do kernel sem processo
- Unificar Debian+Arch+Nix num único rootfs “mágico” na fundação
- Copiar código de terceiros sem avaliação de licença
- Tratar Missão 001 como “distro bootável”

---

## Sugestão de próxima missão

**Missão 006 (após review 005):** autorizar install QEMU + `RYOKU_FETCH_EXECUTE=1`, capturar serial evidence de Alpine reference boot; **ou** pin LTS do kernel + inventário de licença do Ryoku Desktop. Continuar sem ISO Ryoku. Branch protection / Advisories no GitHub se ainda pendentes.
