# Estratégia de testes QEMU/KVM — Ryoku OS

**Estado:** estratégia Missão 001 · harness T0/T1 implementado na **Missão 003** (`ryoku-virtlab`)  
**Ambiente de fundação:** `/dev/kvm` pode existir sem permissão; QEMU frequentemente **ausente**. Nenhuma instalação de pacote é feita pelo harness. Ver [virtual-lab.md](virtual-lab.md).

## Objetivos

Automatizar, de forma progressiva, a confiança de que o Ryoku OS:

1. **Boota** até um ponto observável (firmware → kernel → init/userland).
2. Emite **logs** capturáveis (serial/console) para regressão.
3. Exercita o **instalador** (quando existir) de ponta a ponta.
4. Sobrevive a **reboot** pós-instalação.
5. Evolui para **testes gráficos** (Desktop) sem bloquear os smokes headless.

## Princípios

| Princípio | Detalhe |
|-----------|---------|
| Progressivo | Headless/serial antes de GPU; smoke antes de suite longa |
| Determinístico | Imagens e seeds fixos; timeouts explícitos |
| Observável | Sempre gravar serial log + exit code do QEMU |
| Isolado | Workdirs sob `tests/qemu/run/` (gitignored) |
| Honesto | CI vermelha se QEMU/KVM ausente *quando o job exigir*; jobs docs-only não fingem boot |
| Seguro | Sem rede aberta por padrão; sem credenciais reais nas imagens |

## Fases de automação

### Fase T0 — Doctor + validação do lab (Missões 002–003)

- `ryoku-doctor`: `qemu-system-x86_64` / `qemu-img`, `/dev/kvm`, TCG possível?
- `ryoku-virtlab t0`: configs, bloqueio de discos físicos, argv seguro, limites CPU/RAM/tempo

### Fase T1 — Emulator smoke / boot smoke

**Missão 003 (entregue):** emulator start opcional; **SKIPPED** sem QEMU; OS boot **NOT_RUN** sem imagem autorizada.

**Futuro (imagem de referência autorizada):**

- Cloud image mínima *somente* para validar o harness (sem download automático nesta fase).
- QEMU com KVM se usável, senão TCG; `-nographic`; disco throwaway sob `tests/qemu/run/`
- Critério de boot: sentinelas no serial; artefatos em `tests/qemu/results/` (gitignored)

### Fase T2 — Logs e regressão

- Guardar trechos esperados (regex) em `tests/qemu/expectations/` (texto pequeno no git).
- Falhar se kernel oops/panic conhecido aparecer.
- Upload de logs só como artefato de CI (não commit de logs grandes).

### Fase T3 — Instalador

Quando `packaging/` tiver instalador:

1. Boot do meio de instalação (ISO ou netboot).
2. Drive preseed/autoinstall (não GUI frágil no início).
3. Desligar VM limpa.
4. Critério: exit 0 do script orquestrador + sentinelas no log.

### Fase T4 — Reboot pós-instalação

1. Anexar o disco instalado (sem mídia de instalação).
2. Boot → multi-user / graphical.target conforme perfil.
3. Rodar checklist: `systemctl is-system-running`, versão Zaquion, etc.
4. Reboot novamente e repetir checklist (detectar falha de “só funciona no primeiro boot”).

### Fase T5 — Testes gráficos (progressivo)

Depende do port do Ryoku Desktop:

| Degrau | Técnica | Critério |
|--------|---------|----------|
| G1 | Boot até display manager (virtio-gpu) | Log + opcional screenshot via QEMU `screendump` |
| G2 | Login automatizado (se seguro em CI) | Sessão user ativa |
| G3 | Golden image / diff perceptual leve | Tolerância documentada; flaky ≠ silent pass |
| G4 | Interação (AT-SPI / tools) | Só depois de G1–G3 estáveis |

Headless continua obrigatório na CI padrão; gráfico pode ser job noturno ou `workflow_dispatch`.

## Layout proposto do harness

```
tests/qemu/
├── README.md
├── expectations/          # regex/sentinels (git)
├── fixtures/              # metadados pequenos; NÃO ISOs grandes
├── scripts/               # orquestradores (futuro)
└── run/                   # gitignored: disks, logs, nvram
```

ISOs e qcow2 **não** entram no Git (ver `.gitignore`).

## Matriz de perfis (futuro)

| Perfil | Boot smoke | Instalador | Reboot | Gráfico |
|--------|------------|------------|--------|---------|
| Lite | sim | sim | sim | opcional |
| Full | sim | sim | sim | sim (quando Desktop) |
| Gaming | sim | sim | sim | sim + checks de GPU virt |
| Server | sim | sim | sim | não (headless only) |

## O que a Missão 001 **não** fez

- Não instalou QEMU
- Não criou discos, ISOs ou VMs
- Não executou boots
- Não afirma que testes passaram

## Próximo passo sugerido

Missão de harness T0+T1: doctor + script de boot de imagem de referência + captura de serial, sem ISO Ryoku.
