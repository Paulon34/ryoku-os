# Decisão de layout do repositório

## Decisão

**Usar `/workspace` como raiz do monorepo `ryoku-os`.**

Não criar um subdiretório `ryoku-os/` dentro do workspace.

## Contexto

- O workspace Cloud Agent já é um repositório Git em `/workspace` (apenas `.git` no início da Missão 001).
- Não foram encontrados projetos locais existentes chamados `ryoku-os`, `ryoku-desktop` ou `ryoku-nixos` neste ambiente (busca read-only sob `/home`, `/opt`, `/workspace`, `/usr/local/src`).
- A missão pede preservar espaço conceitual para **Ryoku Desktop** e **ryoku-nixos**, sem inventar cópias.

## Alternativas consideradas

| Opção | Prós | Contras | Resultado |
|-------|------|---------|-----------|
| A. Monorepo na raiz `/workspace` | Alinha com o Git já existente; paths simples; CI trivial | Nome do remoto temporário pode não ser `ryoku-os` até republicação | **Escolhida** |
| B. Subdir `/workspace/ryoku-os/` | Deixa irmãos `ryoku-desktop/`, `ryoku-nixos/` no mesmo workspace | Aninha um repo dentro de outro sem necessidade; confunde `git` atual | Rejeitada enquanto não houver irmãos no disco |
| C. Três clones separados já nesta missão | Separação forte | Não há clones existentes; inventaria estrutura sem fonte | Rejeitada |

## Projetos irmãos (preservados, não inventados)

| Nome | Tratamento neste monorepo |
|------|---------------------------|
| **Ryoku Desktop** | Referência externa. Pasta `apps/` documenta que o Desktop **não** é copiado aqui. Integração futura via submodule, pacote ou missão de port. |
| **ryoku-nixos** | Referência externa / flake futuro. Espaço em `compatibility/nix/` para notas de integração — **sem** copiar um tree NixOS inventado. |

Se no futuro Desktop e NixOS forem colocados como clones irmãos no mesmo disco (fora deste Git), a opção B pode ser revisitada por ADR. Até lá, a raiz atual **é** o `ryoku-os`.

## Mapa de pastas

```
/workspace                          # ryoku-os (este Git)
├── zaquion-core/                   # Rust first-party
├── kernel/                         # referência; sem fonte Linux vendored
├── apps/                           # apps Ryoku; Desktop = externo
├── compatibility/{nix,debian,arch}/
├── packaging/profiles/             # Lite, Full, Gaming, Server
├── tests/qemu/                     # harness futuro
├── docs/
└── .github/
```

## Justificativa técnica

1. **Um Git = um produto fundacional** — documentação, core, packaging e testes evoluem juntos no início.
2. **Kernel separado conceitualmente** — pasta `kernel/` sem tree GPLv2 completo evita misturar obrigações sem processo.
3. **Compatibilidade isolada** — Nix/Debian/Arch ganham namespaces sem fingir unificação de rootfs.
4. **Desktop fora** — evita dual-licensing e histórico de GUI misturados antes do port controlado.
