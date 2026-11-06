# Estratégia de testes QEMU/KVM — Ryoku OS

**Estado:** documentado na Missão 001 · **Execução:** não realizada nesta missão  
**Ambiente de fundação:** `/dev/kvm` presente; binários QEMU **não** instalados (sem `qemu-system-x86_64`). Nenhuma instalação de pacote foi feita.

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

### Fase T0 — Doctor (pré-requisito)

Script futuro `scripts/ryoku-doctor.sh` (Missão 002 sugerida) deve reportar:

- `qemu-system-x86_64` / `qemu-img` presentes?
- `/dev/kvm` acessível?
- Aceleração: KVM vs TCG (fallback lento, marcado como tal)

**Missão 001:** inspeção manual apenas — KVM device existe; QEMU packages não instalados.

### Fase T1 — Boot smoke (imagem de referência)

Antes da ISO Ryoku:

- Usar uma **cloud image** ou imagem mínima de referência (Debian/Ubuntu cloud) *somente* para validar o harness.
- QEMU com:
  - `-enable-kvm` quando disponível
  - `-nographic` ou `-serial stdio`
  - disco qcow2 throwaway
  - cloud-init seed opcional para SSH efêmero
- Critério de sucesso: string sentinel no serial (ex.: kernel panic ausente + “login” ou cloud-init “finished”) em timeout ≤ N minutos.
- Artefatos: `serial.log`, `qemu.stdout`, metadados JSON (duração, exit code).

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
