# Estratégia de licensing — Ryoku OS

**Status:** proposto na Missão 001 · **Não** se adotou uma única licença para todos os componentes.

## Objetivo

Permitir:

- Cumprir obrigações do **Linux kernel** (e de qualquer código derivado GPLv2).
- Publicar **Zaquion Core** e apps first-party com licenças claras e compatíveis com a distribuição.
- Integrar **Nix / Debian / Arch** sem “relicenciar” pacotes de terceiros.
- Evitar misturar código incompatível no mesmo binário/módulo sem análise.

## Princípio central

> **Licença por componente (e por árvore), com inventário SPDX e fronteiras de linkagem documentadas — nunca um SPDX global cego.**

## Mapa preliminar de componentes

| Componente | Local | Licença proposta (fundação) | Notas de compatibilidade |
|------------|-------|-------------------------------|---------------------------|
| Linux kernel (upstream) | Referência em `kernel/` — fonte **não** vendored aqui | **GPLv2-only** (kernel.org) | Qualquer *derivative work* do kernel permanece GPLv2. Módulos `.ko` têm regras específicas; consultar kernel licensing FAQ. |
| Patches Ryoku ao kernel (futuro) | Processo futuro | GPLv2-only | Obrigatório alinhar ao kernel; sem blobs proprietários no tree. |
| Zaquion Core (Rust userland) | `zaquion-core/` | **Apache-2.0 OR MIT** (dual) — **adotado na Missão 002** (`LICENSE-MIT` + `LICENSE-APACHE`) | Adequado a userland; **não** “contamina” o kernel se permanecer em espaço de usuário e sem link estático indevido com obras GPL de forma a criar derivado. Revisar caso a caso se linkar libs GPL. |
| Bibliotecas Zaquion usadas só em userland | `zaquion-core/` | Apache-2.0 OR MIT | Preferir dependências crates.io com licenças permissivas ou GPL compatíveis conforme uso. Missão 002: **zero** deps externas no `ryoku-doctor`. |
| Apps first-party | `apps/` | Avaliar por app; default candidato Apache-2.0 OR MIT | Se um app incorporar código GPL, o app pode precisar ser GPL. |
| Ryoku Desktop (externo) | Fora deste repo | **Seguir licença do projeto existente** | Port não muda a licença original sem acordo dos titulares. Inventariar antes do port. |
| Scripts de packaging / harness | `packaging/`, `tests/` | Apache-2.0 OR MIT *candidato* | Scripts que embutem bits GPL devem isolar e atribuir. |
| Documentação | `docs/`, READMEs | **CC-BY-4.0** *candidato* para prosa; código embutido segue a licença do componente | Evitar copiar manuais de terceiros verbatim. |
| Pacotes Debian/Arch/Nix de terceiros | `compatibility/` (consumo) | **Licença de cada pacote upstream** | Redistribuir em ISO exige compliance (attribution, source offer para GPL, etc.). |

> *Candidato* = recomendação da Missão 001 para decisão formal na primeira missão que adicionar código fonte. Até lá, **não** há arquivos `LICENSE` de código de produção porque não há código de produção.

## Por que não “tudo GPLv3” ou “tudo MIT”?

| Escolha única | Problema |
|---------------|----------|
| Tudo MIT/Apache | **Incompatível** com obrigações se o tree incluir kernel ou derivados GPL sem dual-licensing impossível do Linux. |
| Tudo GPLv2 | Possível para derivados do kernel, mas **desnecessariamente restritivo** para crates Rust first-party e inibe adoção de libs Apache-2.0-only sem análise; GPLv2 vs GPLv3 também diverge. |
| Tudo GPLv3 | **Incompatível** com Linux kernel (GPLv2-only). |
| Um LICENSE na raiz cobrindo tudo | Cria falsa impressão legal; misturaria docs, scripts e (futuro) kernel. |

## Kernel: obrigações a preservar

1. **GPLv2-only** — o kernel Linux não é GPLv3; não relicenciar.
2. **Source offer** — distribuir binários do kernel (ex.: numa ISO) implica disponibilizar fonte correspondente dos derivados.
3. **Não misturar** firmware proprietário *no tree* sem cumprir regras de blobs; preferir `linux-firmware` separado com licenças próprias.
4. **Módulos** — código linkado ao kernel como módulo geralmente precisa de licença compatível (`MODULE_LICENSE`). Código userland falando via syscall/netlink **não** se torna automaticamente GPL só por isso — mas cópia de headers/código GPL pode criar derivado; revisar com cuidado.
5. **Rust no kernel (futuro)** — seguir as regras do projeto rust-for-linux / LKML; não assumir que crates userland Apache podem ser copiados para o tree do kernel.

## Zaquion Core: recomendação

- Adotar **dual MIT OR Apache-2.0** no primeiro crate, alinhado ao ecossistema Rust.
- Manter **fronteira userland**: processos separados, IPC documentado.
- Se no futuro um componente Zaquion for **módulo de kernel**, esse componente específico deve ser GPLv2-compatible e viver sob processo de kernel — possivelmente árvore/licença distinta do restante do Core.

## ISO e redistribuição

Uma ISO Ryoku tipicamente agrega:

- Kernel (GPL) + userland misto + possivelmente firmware + Desktop

Checklist futuro (missão de packaging):

- [ ] Inventário SPDX de todos os pacotes incluídos
- [ ] Arquivos `NOTICE` / `copyright` (estilo Debian) ou equivalente
- [ ] Oferta de fonte para componentes GPL/LGPL
- [ ] Exclusão ou marcação clara de componentes non-free (se houver)
- [ ] Licença do instalador e scripts Ryoku

## Documentação neste repositório (Missão 001)

- Prosa da fundação: tratada como documentação do projeto; candidatos CC-BY-4.0 na formalização.
- Templates GitHub: mesma política de docs.
- **Nenhum** código de terceiro foi copiado nesta missão.

## Processo para adicionar dependência

1. Identificar SPDX e titulares.
2. Registrar em tabela de inventário (a criar em `docs/licensing/inventory.md` quando houver deps).
3. Verificar uso: link estático, dinâmico, source copy, apenas CLI externa.
4. Se dúvida com GPL/LGPL/kernel: abrir issue `licensing` antes do merge.

## Decisão explícita da Missão 001 (atualizada na 002)

**Não** criar um único `LICENSE` na raiz afirmando que “todo o Ryoku OS é X”.

Em vez disso:

- Estratégia por componente (este documento).
- Missão 002: `zaquion-core/LICENSE-MIT` + `zaquion-core/LICENSE-APACHE` + `license = "MIT OR Apache-2.0"` nos crates.
- Quando docs forem formalizadas, `docs/LICENSE` ou NOTICE CC-BY-4.0.
- Kernel permanece upstream com sua licença; sem vendor nesta fase.

## Referências

- Linux kernel COPYING / GPLv2
- Kernel documentation: license rules / GPL
- SPDX license list
- Rust ecosystem dual-licensing norms (MIT OR Apache-2.0)
- Debian `copyright` format (para ISO futura)
