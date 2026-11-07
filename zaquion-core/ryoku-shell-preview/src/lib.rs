//! Ryoku Shell Preview — illustrative desktop layout (Mission 015).
//!
//! Draws a navy/teal top panel, desktop area, dock, and status into an RGB888
//! software buffer. Presentation to `/dev/fb0` reuses Mission 014.2 validation
//! (`ryoku-graphics-demo`). Input (evdev) is **015.1 / NOT_RUN**.
//!
//! Components are illustrative until mouse/keyboard — documented, not interactive.

#![forbid(unsafe_code)]

use ryoku_graphics_demo::{blit_rgb_to_fb, FbGeometry, RgbBuffer};

pub const SHELL_IDENTITY: &str = "ryoku-shell-preview";

/// Brand / chrome colors (navy + teal).
pub const COLOR_NAVY: (u8, u8, u8) = (0x0a, 0x16, 0x2e);
pub const COLOR_NAVY_DEEP: (u8, u8, u8) = (0x06, 0x0e, 0x1c);
pub const COLOR_TEAL: (u8, u8, u8) = (0x2d, 0xd4, 0xbf);
pub const COLOR_TEAL_DIM: (u8, u8, u8) = (0x14, 0x78, 0x6c);
pub const COLOR_PANEL: (u8, u8, u8) = (0x0f, 0x1f, 0x38);
pub const COLOR_TEXT: (u8, u8, u8) = (0xe8, 0xf0, 0xff);
pub const COLOR_MUTED: (u8, u8, u8) = (0x8a, 0xa0, 0xb8);
pub const COLOR_DOCK: (u8, u8, u8) = (0x12, 0x24, 0x40);

/// Layout metrics for a given framebuffer size (works at Paulo's 941×474).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellLayout {
    pub width: u32,
    pub height: u32,
    pub panel_h: u32,
    pub dock_h: u32,
    pub dock_w: u32,
    pub dock_x: u32,
    pub dock_y: u32,
    pub desktop_y: u32,
    pub desktop_h: u32,
}

impl ShellLayout {
    /// Compute responsive chrome sizes. Rejects tiny surfaces.
    pub fn for_fb(width: u32, height: u32) -> Result<Self, String> {
        if width < 320 || height < 200 {
            return Err(format!(
                "{SHELL_IDENTITY}: FB too small for shell preview ({width}x{height}; need ≥320x200)"
            ));
        }
        let panel_h = (height / 16).clamp(24, 40);
        let dock_h = (height / 10).clamp(40, 64);
        let dock_w = (width * 55 / 100).clamp(200, width.saturating_sub(40));
        let dock_x = width.saturating_sub(dock_w) / 2;
        let dock_y = height.saturating_sub(dock_h + 8);
        let desktop_y = panel_h;
        let desktop_h = dock_y.saturating_sub(desktop_y);
        Ok(Self {
            width,
            height,
            panel_h,
            dock_h,
            dock_w,
            dock_x,
            dock_y,
            desktop_y,
            desktop_h,
        })
    }
}

/// Tiny 5×7 glyphs (subset for shell chrome).
fn glyph(ch: char) -> Option<[u8; 7]> {
    match ch {
        ' ' => Some([0, 0, 0, 0, 0, 0, 0]),
        '-' => Some([0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00]),
        '.' => Some([0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C]),
        '/' => Some([0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00]),
        '0' => Some([0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E]),
        '1' => Some([0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E]),
        '2' => Some([0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F]),
        '5' => Some([0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E]),
        'A' => Some([0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11]),
        'C' => Some([0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E]),
        'D' => Some([0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E]),
        'E' => Some([0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F]),
        'H' => Some([0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11]),
        'I' => Some([0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E]),
        'K' => Some([0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11]),
        'L' => Some([0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F]),
        'M' => Some([0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11]),
        'N' => Some([0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11]),
        'O' => Some([0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E]),
        'P' => Some([0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10]),
        'R' => Some([0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11]),
        'S' => Some([0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E]),
        'T' => Some([0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04]),
        'U' => Some([0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E]),
        'V' => Some([0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04]),
        'W' => Some([0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11]),
        'Y' => Some([0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04]),
        _ => None,
    }
}

fn put(buf: &mut RgbBuffer, x: i32, y: i32, rgb: (u8, u8, u8)) {
    if x < 0 || y < 0 {
        return;
    }
    buf.put_pixel(x as u32, y as u32, rgb);
}

/// Axis-aligned filled rectangle (clipped).
pub fn fill_rect(buf: &mut RgbBuffer, x: i32, y: i32, w: i32, h: i32, rgb: (u8, u8, u8)) {
    if w <= 0 || h <= 0 {
        return;
    }
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + w).min(buf.width as i32);
    let y1 = (y + h).min(buf.height as i32);
    for yy in y0..y1 {
        for xx in x0..x1 {
            put(buf, xx, yy, rgb);
        }
    }
}

/// Soft rounded rectangle (corner radius capped).
pub fn fill_rounded(
    buf: &mut RgbBuffer,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    radius: i32,
    rgb: (u8, u8, u8),
) {
    let r = radius.clamp(0, w.min(h) / 2);
    fill_rect(buf, x + r, y, w - 2 * r, h, rgb);
    fill_rect(buf, x, y + r, w, h - 2 * r, rgb);
    // Corner discs (approx).
    for dy in -r..r {
        for dx in -r..r {
            if dx * dx + dy * dy <= r * r {
                put(buf, x + r + dx, y + r + dy, rgb);
                put(buf, x + w - 1 - r + dx, y + r + dy, rgb);
                put(buf, x + r + dx, y + h - 1 - r + dy, rgb);
                put(buf, x + w - 1 - r + dx, y + h - 1 - r + dy, rgb);
            }
        }
    }
}

/// Draw uppercase-capable text at scale.
pub fn draw_text(buf: &mut RgbBuffer, x: i32, y: i32, text: &str, scale: i32, rgb: (u8, u8, u8)) {
    let scale = scale.max(1);
    let mut cx = x;
    for ch in text.chars() {
        let up = if ch.is_ascii_alphabetic() {
            ch.to_ascii_uppercase()
        } else {
            ch
        };
        if let Some(rows) = glyph(up) {
            for (ry, row) in rows.iter().enumerate() {
                for bx in 0..5i32 {
                    if row & (1 << (4 - bx)) != 0 {
                        for sy in 0..scale {
                            for sx in 0..scale {
                                put(buf, cx + bx * scale + sx, y + ry as i32 * scale + sy, rgb);
                            }
                        }
                    }
                }
            }
        }
        cx += 6 * scale;
    }
}

/// Simple square “icon” placeholder (illustrative — not clickable until 015.1).
pub fn draw_icon(buf: &mut RgbBuffer, x: i32, y: i32, size: i32, accent: (u8, u8, u8)) {
    fill_rounded(buf, x, y, size, size, size / 5, COLOR_PANEL);
    fill_rounded(
        buf,
        x + size / 5,
        y + size / 5,
        size - 2 * (size / 5),
        size - 2 * (size / 5),
        size / 8,
        accent,
    );
}

/// Compose the full shell chrome into `buf` (must already match layout size).
pub fn compose_shell(buf: &mut RgbBuffer, layout: &ShellLayout) {
    // Desktop wallpaper (vertical navy→deep gradient).
    for y in 0..buf.height {
        let t = y * 255 / buf.height.max(1);
        let r = COLOR_NAVY.0 as u32
            + (COLOR_NAVY_DEEP.0 as u32).saturating_sub(COLOR_NAVY.0 as u32) * t / 255;
        let g = COLOR_NAVY.1 as u32 * (255 - t) / 255 + COLOR_NAVY_DEEP.1 as u32 * t / 255;
        let b = COLOR_NAVY.2 as u32 * (255 - t) / 255 + COLOR_TEAL_DIM.2 as u32 * t / 400;
        fill_rect(
            buf,
            0,
            y as i32,
            buf.width as i32,
            1,
            (r as u8, g as u8, b.min(255) as u8),
        );
    }

    // Top panel
    fill_rect(
        buf,
        0,
        0,
        layout.width as i32,
        layout.panel_h as i32,
        COLOR_PANEL,
    );
    fill_rect(
        buf,
        0,
        layout.panel_h as i32 - 2,
        layout.width as i32,
        2,
        COLOR_TEAL_DIM,
    );
    let text_scale = if layout.width >= 800 { 2 } else { 1 };
    draw_text(buf, 12, 8, "RYOKU", text_scale, COLOR_TEAL);
    draw_text(
        buf,
        12 + 6 * 5 * text_scale + 8,
        8,
        "SHELL PREVIEW",
        text_scale,
        COLOR_TEXT,
    );
    // Status (right) — illustrative clock/status; not live.
    let status = "DEV PREVIEW";
    let status_w = status.len() as i32 * 6 * text_scale;
    draw_text(
        buf,
        layout.width as i32 - status_w - 12,
        8,
        status,
        text_scale,
        COLOR_MUTED,
    );

    // Desktop hint card (illustrative)
    if layout.desktop_h > 80 {
        let card_w = (layout.width as i32 * 45 / 100).clamp(220, 420);
        let card_h = (layout.desktop_h as i32 / 3).clamp(70, 120);
        let card_x = (layout.width as i32 - card_w) / 2;
        let card_y = layout.desktop_y as i32 + (layout.desktop_h as i32 - card_h) / 3;
        fill_rounded(buf, card_x, card_y, card_w, card_h, 10, COLOR_PANEL);
        draw_text(
            buf,
            card_x + 16,
            card_y + 18,
            "MINIMAL DEVELOPER PREVIEW",
            text_scale,
            COLOR_TEXT,
        );
        draw_text(
            buf,
            card_x + 16,
            card_y + 18 + 10 * text_scale + 8,
            "INPUT NOT_RUN - 015.1",
            text_scale,
            COLOR_MUTED,
        );
    }

    // Dock
    fill_rounded(
        buf,
        layout.dock_x as i32,
        layout.dock_y as i32,
        layout.dock_w as i32,
        layout.dock_h as i32,
        12,
        COLOR_DOCK,
    );
    let icon = (layout.dock_h as i32 - 16).clamp(24, 48);
    let slots = 5i32;
    let gap = (layout.dock_w as i32 - slots * icon) / (slots + 1);
    for i in 0..slots {
        let ix = layout.dock_x as i32 + gap + i * (icon + gap);
        let iy = layout.dock_y as i32 + (layout.dock_h as i32 - icon) / 2;
        let accent = if i == 0 { COLOR_TEAL } else { COLOR_TEAL_DIM };
        draw_icon(buf, ix, iy, icon, accent);
    }
}

/// Build an RGB software buffer with the shell layout for the given FB size.
pub fn render_shell(width: u32, height: u32) -> Result<(RgbBuffer, ShellLayout), String> {
    let layout = ShellLayout::for_fb(width, height)?;
    let mut buf = RgbBuffer::new(layout.width, layout.height, COLOR_NAVY);
    compose_shell(&mut buf, &layout);
    Ok((buf, layout))
}

/// Present shell buffer into an fb mmap (reuses 014.2 blit).
pub fn present_shell(map: &mut [u8], geom: &FbGeometry, src: &RgbBuffer) -> Result<(), String> {
    blit_rgb_to_fb(map, geom, src).map_err(|e| format!("{SHELL_IDENTITY}: blit failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layout_paulo_941x474() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        assert_eq!(l.width, 941);
        assert!(l.panel_h >= 24 && l.panel_h <= 40);
        assert!(l.dock_y + l.dock_h <= l.height);
        assert!(l.desktop_h > 0);
    }

    #[test]
    fn layout_rejects_tiny() {
        assert!(ShellLayout::for_fb(100, 80).is_err());
    }

    #[test]
    fn render_marks_teal_brand_pixels() {
        let (buf, _) = render_shell(941, 474).unwrap();
        assert!(buf
            .pixels
            .windows(3)
            .any(|p| p == [COLOR_TEAL.0, COLOR_TEAL.1, COLOR_TEAL.2]));
    }

    #[test]
    fn present_shell_padded_stride() {
        let geom = FbGeometry {
            width: 320,
            height: 240,
            bpp: 32,
            stride: 1280 + 64, // padded
        };
        let (src, _) = render_shell(320, 240).unwrap();
        let need = geom.stride as usize * geom.height as usize;
        let mut map = vec![0u8; need];
        present_shell(&mut map, &geom, &src).unwrap();
        assert!(map.iter().any(|&b| b != 0));
    }

    #[test]
    fn fill_rect_clips_oob() {
        let mut buf = RgbBuffer::new(10, 10, (0, 0, 0));
        fill_rect(&mut buf, -5, -5, 8, 8, (1, 2, 3));
        assert_eq!(buf.pixels[0], 1);
    }

    #[test]
    fn no_gpu_claim_in_identity() {
        assert!(!SHELL_IDENTITY.contains("wayland"));
        assert!(!SHELL_IDENTITY.contains("gpu"));
    }
}
