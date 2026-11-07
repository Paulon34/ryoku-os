# Ryoku Adaptive Performance (Mission 016.1) — CLOSEOUT

**Merge:** não. Tip validado (manual NixOS): **`d2785f4335264159b582ec7d3d129a86509ccf4e`**.

CI ≠ guest. Never invent `PASS_MANUAL` from host unit tests or package CI.

## Evidência manual (NixOS)

- Boot / PID1 / console OK; 14/14 modules; DRM/fbdev; teclados + tablet
- Perfis Balanced / Lite / Ultra; amostras reais de métricas (serial)
- Exemplos observados (TCG; **não** benchmark controlado):
  - BALANCED n=78 c≈6253µs p≈4594µs
  - LITE n=49 / 44 (janelas mistas)
  - ULTRA→BALANCED n=49; scratch ≈2737 KiB

## Claims oficiais (≠ CI)

| Item | Status |
|------|--------|
| **`ADAPTIVE_PERF_GUEST`** | **`PASS_MANUAL`** |
| **`PROFILE_SWITCH`** | **`PASS_MANUAL`** |
| **`PERF_METRICS`** | **`PASS_MANUAL`** |
| **`CONTROLLED_BENCHMARK`** | **`NOT_RUN`** |

### Honesty explícita

- **Não** concluir que Lite é mais lento: janelas misturam full vs band frames
- **Não** declarar blur / efeitos Ultra (Ultra → Balanced paint fallback)
- QEMU TCG ≠ hardware; amostras ad-hoc ≠ harness controlado

## Next

Mission **016.2** — Controlled Performance (benchmark determinístico; guest até manual).

## Related

- Closeout 016: [`ryoku-adaptive-016.md`](ryoku-adaptive-016.md)
- Package: [`tests/qemu/README-ADAPTIVE-PERF.md`](../../tests/qemu/README-ADAPTIVE-PERF.md)
