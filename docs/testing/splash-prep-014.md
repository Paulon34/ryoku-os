# Splash / banner prep (Mission 014 — documentation only)

Mission 013 ships a **plain ASCII** banner from `ryoku-init` after READY (and
after proc/sys mount attempts) and before spawning `ryoku-console`.

```text
========================================
  Ryoku Minimal
  interactive lab console
  (not a product OS boot)
========================================
```

## Mission 014 scope (not implemented here)

| Item | 013 | 014 (future) |
|------|-----|--------------|
| Plain ASCII honesty banner | **yes** | keep as fallback |
| Branded splash / artwork | **no** | design + optional asset |
| Guest boot claim | **NOT_RUN** for 013 | still requires manual/CI evidence |
| Product OS splash | **no** | **no** until product boot exists |

Do **not** treat the ASCII banner as a product boot splash. T3 Boot Seed path
must remain free of decorative banners that could confuse evidence logs (013
prints the banner only on the Minimal interactive path).
