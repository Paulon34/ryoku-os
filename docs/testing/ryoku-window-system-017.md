# Ryoku Window System (Mission 017)

**Guest results:** **`GUEST_NOT_RUN`** until human confirm (never auto `PASS_MANUAL`).

Stacked on Mission **016.2** (`5ee96b1`, CONTROLLED_BENCHMARK guest **NOT_RUN** preserved).

## Delivered (code)

- In-process `WindowManager`: geometry, focus, z-order, events, dirty rects
- Internal windows only (`WindowKind::Demo` …) — **no** external app exec
- Move / resize / minimize / maximize / close chrome
- Compose under launcher modal; no visible fb clear; Adaptive Ultra→Balanced paint unchanged

## Honesty

| Claim | Status |
|-------|--------|
| Wayland compositor | **Not** claimed |
| External app launch | **Not** claimed |
| Guest WM confirm | **`GUEST_NOT_RUN`** |
| CONTROLLED_BENCHMARK guest | **NOT_RUN** (preserved) |

## Manual

Launcher → SYSTEM (or Enter on SYSTEM) opens **WM DEMO**. Drag titlebar; resize SE edge; `_` minimize, `O` maximize, `X` close.

## Related

- Architecture: [`../architecture/RYOKU_DESKTOP_ARCHITECTURE.md`](../architecture/RYOKU_DESKTOP_ARCHITECTURE.md)
- Package: [`../../tests/qemu/README-WINDOW.md`](../../tests/qemu/README-WINDOW.md)
