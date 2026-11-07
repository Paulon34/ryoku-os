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
- [x] Workflow `first-boot.yml` — `workflow_dispatch` + `confirm=RUN` (Missão 006; sem `if: false`)
- [x] Fetch script: allowlist CDN + SHA-256 pin + GPG ncopa (Missão 006)
- [x] Marcadores seriais Alpine (`Alpine|login:`) + evidence JSON (Missão 006)
- [x] First-boot Actions real **PASS** (Missão 007.1 — Alpine TCG serial; ≠ Ryoku OS)
- [ ] Smoke: boot → login/ssh → shutdown em imagem autorizada
- [ ] Artefatos de expectativa extras (texto pequeno no git)

Ver [docs/testing/reference-linux.md](docs/testing/reference-linux.md), [virtual-lab.md](docs/testing/virtual-lab.md).

## Fase 2.5 — Boot Seed / T3 (Missões 008–010)

- [x] ADR-0002 + `ryoku-init` + initramfs + `t3-boot-seed` (Missão 008; merge `4b9305b`)
- [x] Missão 009 prep + 009.5 harden/merge (`5a9d67d`)
- [x] Missão 010: **um** dispatch autorizado `boot-seed-t3` — serial `pid=1` + READY (seed ≠ produto)
- [ ] Boot de produto Ryoku OS (ainda **não** — seed ≠ produto)

Ver [docs/testing/boot-seed.md](docs/testing/boot-seed.md), [boot-seed-t3.md](docs/testing/boot-seed-t3.md).

## Fase 2.6 — Console interativo (Missão 011) — prep / audit stop

- [x] Crate `ryoku-console` (help/version/status/echo/clear) separado do PID 1
- [x] Parser limitado (sem shell) + testes de segurança
- [x] Perfil QEMU `console-interactive` (`serial_log=stdio`) **sem** substituir T3 file-serial
- [x] Wiring console após READY + Minimal FS (Missão 012)
- [x] Boot guest interativo **PASS_MANUAL** (2026-11-07; ZIP 012.1; ≠ CI)
- [ ] Claim de shell de produto (nunca nesta fase)

Ver [docs/testing/console.md](docs/testing/console.md), [ryoku-minimal.md](docs/testing/ryoku-minimal.md).

## Fase 2.7 — Ryoku Minimal (Missão 012 / 012.1) — closeout

- [x] `ryoku-init` spawna `ryoku-console` uma vez após READY (se `/bin/ryoku-console` existir)
- [x] Initramfs experimental separado do T3 (`ryoku-minimal.cpio.gz`)
- [x] Builtins `pwd` / `ls` / `cat` + testes sem QEMU
- [x] Perfil interativo + planos de harness
- [x] Hardening FS (symlinks/cap/host root) + `!` em echo
- [x] Pacote VM self-contained (musl + cpio + lab kernel + launcher hash gate)
- [x] Sessão QEMU guest autorizada — **`interactive_guest_boot=PASS_MANUAL`** (Paulo; tip `fecc0b5`; CI ≠ boot)
- [ ] `clear` guest; product OS boot (não claims)

## Fase 2.8 — Hardware probe (Missão 013) — closeout

- [x] Mount `proc`/`sys` após READY (antes do console); WARN se falhar; T3 intacto
- [x] Crate `ryoku-hwprobe` + builtins `hw summary|cpu|pci|drivers`
- [x] Anúncio READY single-channel; banner ASCII; docs splash Missão 014
- [x] Guest 013 **`PASS_MANUAL`** (2026-11-07; tip `649b850`; ≠ CI)
- [x] First pixels / gráfico (Missão 014) — **`FIRST_PIXELS=PASS_MANUAL`** (tip `ca26ac5`; ≠ CI)

## Fase 2.9 — First Pixels (Missão 014 / 014.1 / 014.2) — CLOSED

- [x] Inspeção/documentação DRM/KMS/fb/virtio-gpu (sem claim de driver; sem modules host)
- [x] `hw graphics` + PCI class/bound-driver honesty; perfil QEMU gráfico separado
- [x] `ryoku-graphics-demo` + package workflow separado
- [x] 014.1: Alpine virt DRM modules pin + pack + PID1 controlled load/demo start
- [x] 014.2: fb0 explicit-length mmap + ioctl geometry (014.1 attempt **FAIL_MANUAL**; 014.2 visual **PASS_MANUAL**)
- [x] Guest visual first pixels confirmed (Paulo NixOS QEMU; tip `ca26ac5`)

## Fase 2.10 — Ryoku Shell Preview (Missão 015) — CLOSED

- [x] Layout desktop ilustrativo no framebuffer (panel/dock/status)
- [x] Package gráfico shell separado
- [x] Guest visual **`SHELL_PREVIEW=PASS_MANUAL`** (tip `4b239a0`; ≠ CI)

## Fase 2.11 — Interactive Shell Input (Missão 015.1) — PARTIAL CLOSEOUT

- [x] Guest evdev mouse + keyboard path; event loop; dock hit-test / launcher panel (code)
- [x] QEMU virtio keyboard + tablet; Alpine `evdev` + `virtio_input` modules
- [x] PID1: shell background + serial console + reap (no zombies)
- [x] Manual (tip `f5cc1c4`; ≠ CI): **`SHELL_RENDER=PASS_MANUAL`**, **`DOCK_VISUAL_FEEDBACK=PASS_MANUAL`**, **`GUEST_INPUT=PARTIAL_PASS_MANUAL`**
- [ ] **`LAUNCHER_OPEN` / `KEYBOARD_INTERACTION` / `CURSOR_MOVEMENT` = `NOT_CONFIRMED`** → Mission 015.2

## Fase 2.12 — Interactive Launcher (Missão 015.2 / 015.2.1) — CLOSEOUT

- [x] Ryoku Launcher panel (title/categories/focus/close/adaptive) — code
- [x] ABS axis from device caps; device filter; fact-based indicators (never auto PASS_MANUAL)
- [x] 015.2.1: no visible fb clear; dirty/scanline blit; keep all keyboards; `vt.global_cursor_default=0` (shell QEMU)
- [x] Manual tip `6993807` (≠ CI): **`GRAPHICS_STABILITY=PASS_MANUAL`**, **`MOUSE_LAUNCHER_OPEN=PASS_MANUAL`**, **`LAUNCHER_RENDER=PASS_MANUAL`**
- [ ] **`KEYBOARD_INTERACTION` / `LAUNCHER_CLOSE` = `NOT_CONFIRMED`**
- [x] Prior FAIL preserved: tip `052c84c` **`GRAPHICS_FLICKER=FAIL_MANUAL`**

## Fase 2.13 — Adaptive Desktop Foundation (Missão 016) — CLOSEOUT

- [x] Perfis Lite / Balanced / Ultra (tema, layout, animação, políticas de render) — code
- [x] Troca de perfil na sessão (F1/F2/F3); Ultra → fallback Balanced; métricas compose/blit/mem
- [x] Sem fingir blur/transparência/3D/compositor/Wayland completo; sem redraw contínuo; sem clear visível
- [x] Manual tip `572f77d` (≠ CI): **`ADAPTIVE_PROFILE_SWITCH=PASS_MANUAL`**, **`KEYBOARD_ARROWS_TAB=PASS_MANUAL`**, **`LITE_USABILITY=POSITIVE_MANUAL_FEEDBACK`**, **`BALANCED_USABILITY=POSITIVE_MANUAL_FEEDBACK`**, **`ULTRA_PERCEIVED_SLOWDOWN=REPORTED_UNMEASURED`**, **`PERFORMANCE_BENCHMARK=NOT_RUN`**

## Fase 2.14 — Adaptive Performance (Missão 016.1) — CLOSEOUT

- [x] Instrumentação compose/present; selected vs effective; band compose; overlay off-by-default — code
- [x] Lite vs Balanced compare helpers (samples only); Ultra=Balanced paint investigation; TCG ≠ hardware docs
- [x] Manual tip `d2785f4` (≠ CI): **`ADAPTIVE_PERF_GUEST=PASS_MANUAL`**, **`PROFILE_SWITCH=PASS_MANUAL`**, **`PERF_METRICS=PASS_MANUAL`**, **`CONTROLLED_BENCHMARK=NOT_RUN`**
- [x] Honesty: do **not** conclude Lite slower from mixed full/band windows; no Ultra blur claim

## Fase 2.15 — Controlled Performance (Missão 016.2)

- [x] Benchmark determinístico idêntico por perfil (full vs partial; mean/p95); reset on switch; off no uso normal — code
- [x] QEMU→guest allowlisted `ryoku.*` cmdline; instrumentation cost docs; T3 intact
- [ ] Guest **`CONTROLLED_BENCHMARK=NOT_RUN`** until manual; TCG ≠ físico

## Fase 3 — Primeiros serviços Zaquion Core

- [ ] Definição de IPC/API inicial (ex.: socket + schema versionado)
- [ ] Serviço piloto além do inventário read-only de hardware (013)
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

**Missão 013:** probe de hardware read-only (`proc`/`sys`, `hw *` no console) após Minimal **PASS_MANUAL**.  
**Missão 014 (docs):** splash/banner visual — preparar só documentação após 013. Continuar sem ISO de produto.
