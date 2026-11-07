# Ryoku Shell Preview (Mission 015) — CLOSED

**Closeout:** 2026-11-07 · tip **`4b239a05aabe334f6bca296fd4f19a8e3eb5077c`** · PR #9  
**Official claim:** **`SHELL_PREVIEW=PASS_MANUAL`** (Paulo NixOS QEMU visual; **≠ CI**)  
**Input (015.1):** continues as separate mission — **`NOT_RUN`** here

## Status matrix

| Item | Status | Evidence |
|------|--------|----------|
| Host / package CI | **PASS** | CI |
| Alpine boot / PID1 / 12/12 DRM / virtio_gpu / fb0 | **PASS_MANUAL** | Paulo |
| Shell-preview start + present | **PASS_MANUAL** | 941×474 32bpp; mmap 1784136; panel_h=29 dock 517×47@(212,419); exit 0 |
| Screenshot description | panel / dock / preview chrome | human (no hosted URL invented) |
| **`SHELL_PREVIEW`** | **`PASS_MANUAL`** | ≠ CI |
| Mouse / keyboard / Wayland / full Desktop | **Not** claimed | — |

## What this was

Illustrative Ryoku layout (navy/teal panel, desktop, dock, status) on real `/dev/fb0`
via Mission 014.2 mmap/ioctl. Serial console continued after present.

## Related

- Package: [`tests/qemu/README-SHELL.md`](../../tests/qemu/README-SHELL.md)
- Input next: Mission 015.1
