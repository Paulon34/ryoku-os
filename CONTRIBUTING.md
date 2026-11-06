# Contributing / Contribuindo — Ryoku OS

Obrigado por considerar contribuir. Este guia cobre o fluxo mínimo enquanto o projeto está em fundação.

Thank you for considering a contribution. This guide covers the minimum workflow while the project is foundational.

## Idiomas / Languages

- Issues e PRs: **português ou inglês** (aceitos ambos).
- Documentação de usuário: manter **pares PT/EN** quando o conteúdo for público e estável.
- Código e comentários técnicos: preferir **inglês** (padrão da indústria e do ecossistema Rust/Linux).

## Antes de começar / Before you start

1. Leia [README.md](README.md) / [README.en.md](README.en.md) e [docs/architecture/ADR-0001.md](docs/architecture/ADR-0001.md).
2. Verifique [SECURITY.md](SECURITY.md) para vulnerabilidades (não abra issue pública).
3. Confirme a licença do componente que pretende alterar — ver [docs/licensing/strategy.md](docs/licensing/strategy.md).
4. **Não** copie código de terceiros sem registrar avaliação de licença em `docs/licensing/` ou no PR.

## O que não fazer nesta fase / Out of scope now

- Modificar, baixar ou compilar o kernel Linux neste repositório sem missão explícita
- Gerar ISO ou executar VMs sem harness documentado
- Alterar partições, bootloader ou configuração do host
- Adicionar segredos, credenciais ou dados pessoais
- Inventar cópias de **Ryoku Desktop** ou **ryoku-nixos** — trate-os como projetos irmãos externos

## Fluxo Git / Git workflow

1. Fork (quando o GitHub público existir) ou branch local a partir de `main`.
2. Branches sugeridas: `cursor/<descricao-curta>-XXXX` ou `feat/…`, `docs/…`, `fix/…`.
3. Commits pequenos e descritivos (imperativo: “Add…”, “Document…”).
4. Abra um PR usando o template em `.github/PULL_REQUEST_TEMPLATE.md`.
5. Aguarde revisão; não force-push em `main`.

## Padrões de código / Code standards

Crates Rust em `zaquion-core/` (a partir da Missão 002):

```bash
cd zaquion-core
cargo fmt --all -- --check
cargo check --workspace
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p ryoku-doctor
```

- Preferir stdlib; justificar qualquer crate em `docs/licensing/` + PR
- Sem `unsafe` sem justificativa no PR (`forbid` no workspace)
- MSRV: ver `zaquion-core/README.md` (1.75; toolchain pin 1.83.0)

Documentação:

- Preferir Markdown com links relativos
- ADRs novos: `docs/architecture/ADR-XXXX.md` (numeração sequencial)

## Issues

Use os templates em `.github/ISSUE_TEMPLATE/`:

- Bug report
- Feature request
- Documentation

## Testes / Testing

- Declare o que foi executado e o que **não** foi.
- Não afirme “testes passaram” sem comando e resultado.
- Estratégia QEMU: [docs/testing/qemu-strategy.md](docs/testing/qemu-strategy.md).

## Código de conduta (provisório)

Seja respeitoso. Discusões técnicas, foco no problema. Assédio ou conteúdo ilegal → contato via canal de segurança em [SECURITY.md](SECURITY.md). Um Code of Conduct formal pode ser adotado numa missão futura.
