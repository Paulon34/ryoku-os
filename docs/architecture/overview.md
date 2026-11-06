# Arquitetura — visão geral / Architecture overview

## Português

Ryoku OS é organizado em camadas. A fundação (Missão 001) define **limites**, não uma imagem bootável.

### Componentes

1. **Kernel (Linux upstream)**  
   Base do sistema. Sem patches Ryoku no início. Futuras integrações Rust (ex.: rust-for-linux ou módulos out-of-tree) exigem ADR próprio e processo de rebase.

2. **Zaquion Core**  
   Código first-party em Rust: daemons, CLIs, bibliotecas de sistema. Vive em `zaquion-core/`. Deve ser testável fora do kernel (unit/integration) e depois validado em QEMU.

3. **Userland / compatibilidade**  
   Pacotes e runtimes vindos de Nix, Debian e/ou Arch. O Ryoku OS **não** pretende fundir os três gerenciadores num único solver na fundação. Ver [../compatibility/overview.md](../compatibility/overview.md).

4. **Apps e Ryoku Desktop**  
   Apps próprios podem viver em `apps/`. O **Ryoku Desktop** permanece projeto externo até missão de port.

5. **Packaging**  
   Perfis Lite, Full, Gaming, Server; futuro instalador e ISO sob `packaging/`.

6. **Testes**  
   Harness QEMU/KVM sob `tests/qemu/` — estratégia em [../testing/qemu-strategy.md](../testing/qemu-strategy.md).

### Diagrama lógico

```
Usuário
  → Ryoku Desktop / apps
    → Zaquion Core (Rust services)
      → userland (perfil + adapters de compatibilidade)
        → Linux kernel upstream
          → hardware ou QEMU
```

### Documentos relacionados

- [ADR-0001.md](ADR-0001.md) — decisão fundacional
- [layout.md](layout.md) — por que monorepo na raiz
- [../licensing/strategy.md](../licensing/strategy.md)
- [../testing/qemu-strategy.md](../testing/qemu-strategy.md)

---

## English

Ryoku OS is layered. Mission 001 defines **boundaries**, not a bootable image.

### Components

1. **Kernel (upstream Linux)** — unmodified at first; future Rust integrations need their own ADR.  
2. **Zaquion Core** — first-party Rust services/tools in `zaquion-core/`.  
3. **Userland / compatibility** — Nix, Debian, and/or Arch via integration or isolation — not a merged solver on day one.  
4. **Apps and Ryoku Desktop** — first-party apps may live under `apps/`; Desktop stays external until a port mission.  
5. **Packaging** — Lite / Full / Gaming / Server profiles; future installer and ISO.  
6. **Testing** — QEMU/KVM harness; see the QEMU strategy doc.

See ADR-0001 for the formal decision record.
