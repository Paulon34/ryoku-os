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

## Fase 1 — Bootstrap de ferramenta e CI documental

- [ ] CI mínima: lint de Markdown, checagem de links internos, `cargo fmt`/`clippy` quando houver crates
- [ ] Workspace Cargo inicial em `zaquion-core/` (crate `zaquion-hello` ou equivalente mínimo)
- [ ] Script de doctor do host (detectar Rust, Clang, QEMU, KVM) — sem instalar pacotes automaticamente
- [ ] Política de submódulos / referência ao tree do kernel (pin de versão, sem vendorar fonte completa se evitável)

## Fase 2 — Harness QEMU (sem ISO ainda)

- [ ] Instalar/usar QEMU no ambiente de CI ou dev (fora do escopo da Missão 001)
- [ ] Boot de imagem de referência (ex.: cloud image Debian/Ubuntu) só para validar o harness
- [ ] Captura de serial/console logs
- [ ] Smoke: boot → login/ssh → shutdown
- [ ] Artefatos de log versionados como *fixtures de expectativa*, não como blobs grandes no git

Ver [docs/testing/qemu-strategy.md](docs/testing/qemu-strategy.md).

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

**Missão 002 — Bootstrap Zaquion + doctor + CI documental**: criar o workspace Cargo mínimo, um crate de exemplo, script `scripts/ryoku-doctor.sh` (detecção somente), e workflow GitHub Actions que valide docs + `cargo check` sem construir kernel/ISO.
