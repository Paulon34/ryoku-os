# Live ISO (ENTREGA E) — gated

**Status:** deferred.

Calamares + `live-build` ISO work starts only after the Debian Niri desktop session is manually verified (`GUEST_NOT_RUN` cleared with honest evidence). VMs used for ISO experiments are **discard-only**.

This document intentionally contains **no** ISO build recipes that imply a shippable image exists.

## Prerequisites (all required)

1. ENTREGA A bootstrap `--apply` on Debian 13 Trixie amd64
2. GDM → Ryoku (Niri) session confirmed
3. DMS shell visible (ENTREGA B)
4. Profile knobs exercised (ENTREGA C)
5. `ryoku system-info` works on guest (ENTREGA D)

Until then: do not invent `PASS_MANUAL` for ISO/desktop.
