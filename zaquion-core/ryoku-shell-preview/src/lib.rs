//! Ryoku Shell Preview — illustrative desktop layout (Mission 015 / 015.1 / 015.2).
//!
//! Draws a navy/teal top panel, desktop area, dock, and status into an RGB888
//! software buffer. Presentation to `/dev/fb0` reuses Mission 014.2 validation
//! (`ryoku-graphics-demo`).
//!
//! Mission **015.2** adds the Ryoku Launcher panel (categories/focus/close) and
//! fact-based input indicators (`UNAVAILABLE` / `DETECTED` / `EVENTS RECEIVED`).
//! This crate **never** invents `PASS_MANUAL` from host unit tests or CI.

#![forbid(unsafe_code)]

use ryoku_graphics_demo::{blit_rgb_to_fb, FbGeometry, RgbBuffer};

pub const SHELL_IDENTITY: &str = "ryoku-shell-preview";

/// Dock icon slot count (first icon opens Launcher).
pub const DOCK_SLOTS: usize = 5;

/// Illustrative launcher categories (no app exec).
pub const LAUNCHER_CATEGORIES: &[&str] = &["SYSTEM", "DEV TOOLS", "FILES", "SETTINGS"];

/// Fact-based guest input indicator (Mission 015.2). Never `PASS_MANUAL`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputFact {
    #[default]
    Unavailable,
    Detected,
    EventsReceived,
}

impl InputFact {
    /// Short status label for the top panel (ASCII glyphs available).
    #[must_use]
    pub fn panel_label(self) -> &'static str {
        match self {
            Self::Unavailable => "INPUT UNAVAILABLE",
            Self::Detected => "INPUT DETECTED",
            Self::EventsReceived => "EVENTS RECEIVED",
        }
    }

    pub fn note_event(&mut self) {
        if matches!(self, Self::Detected | Self::EventsReceived) {
            *self = Self::EventsReceived;
        }
    }
}

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

    /// Icon pixel size for the dock.
    #[must_use]
    pub fn icon_size(&self) -> i32 {
        (self.dock_h as i32 - 16).clamp(24, 48)
    }

    /// Gap between dock icons (and edges).
    #[must_use]
    pub fn icon_gap(&self) -> i32 {
        let icon = self.icon_size();
        let slots = DOCK_SLOTS as i32;
        (self.dock_w as i32 - slots * icon) / (slots + 1)
    }

    /// Axis-aligned rect for dock icon `index` → `(x, y, w, h)`.
    #[must_use]
    pub fn dock_icon_rect(&self, index: usize) -> Option<(i32, i32, i32, i32)> {
        if index >= DOCK_SLOTS {
            return None;
        }
        let icon = self.icon_size();
        let gap = self.icon_gap();
        let ix = self.dock_x as i32 + gap + (index as i32) * (icon + gap);
        let iy = self.dock_y as i32 + (self.dock_h as i32 - icon) / 2;
        Some((ix, iy, icon, icon))
    }
}

/// Adaptive launcher geometry for the current FB.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LauncherLayout {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    pub close_x: i32,
    pub close_y: i32,
    pub close_s: i32,
    pub row_y0: i32,
    pub row_h: i32,
}

impl LauncherLayout {
    #[must_use]
    pub fn for_shell(layout: &ShellLayout) -> Self {
        let w = (layout.width as i32 * 42 / 100).clamp(220, 400);
        let h = (layout.desktop_h as i32 * 70 / 100).clamp(160, 320);
        let x = 20;
        let y = layout.desktop_y as i32 + 12;
        let close_s = 18;
        let close_x = x + w - close_s - 10;
        let close_y = y + 10;
        let row_y0 = y + 44;
        let row_h = 28;
        Self {
            x,
            y,
            w,
            h,
            close_x,
            close_y,
            close_s,
            row_y0,
            row_h,
        }
    }

    #[must_use]
    pub fn contains(&self, px: i32, py: i32) -> bool {
        px >= self.x && px < self.x + self.w && py >= self.y && py < self.y + self.h
    }

    #[must_use]
    pub fn hit_close(&self, px: i32, py: i32) -> bool {
        px >= self.close_x
            && px < self.close_x + self.close_s
            && py >= self.close_y
            && py < self.close_y + self.close_s
    }

    #[must_use]
    pub fn hit_category(&self, px: i32, py: i32) -> Option<usize> {
        if !self.contains(px, py) {
            return None;
        }
        for i in 0..LAUNCHER_CATEGORIES.len() {
            let ry = self.row_y0 + (i as i32) * self.row_h;
            if py >= ry && py < ry + self.row_h - 4 {
                return Some(i);
            }
        }
        None
    }
}

/// Interactive UI state (Mission 015.1 / 015.2). Guest PASS is manual only.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InteractiveState {
    pub cursor_x: i32,
    pub cursor_y: i32,
    pub hover_dock: Option<usize>,
    pub selected_dock: Option<usize>,
    pub launcher_open: bool,
    pub launcher_focus: usize,
    pub left_down: bool,
    pub input_fact: InputFact,
}

impl InteractiveState {
    #[must_use]
    pub fn new(layout: &ShellLayout) -> Self {
        Self {
            cursor_x: (layout.width / 2) as i32,
            cursor_y: (layout.height / 2) as i32,
            hover_dock: None,
            selected_dock: None,
            launcher_open: false,
            launcher_focus: 0,
            left_down: false,
            input_fact: InputFact::Unavailable,
        }
    }

    /// Clamp cursor into FB bounds.
    pub fn clamp_cursor(&mut self, layout: &ShellLayout) {
        self.cursor_x = self
            .cursor_x
            .clamp(0, layout.width.saturating_sub(1) as i32);
        self.cursor_y = self
            .cursor_y
            .clamp(0, layout.height.saturating_sub(1) as i32);
    }

    /// Move by relative delta and clamp.
    pub fn move_by(&mut self, layout: &ShellLayout, dx: i32, dy: i32) {
        self.cursor_x += dx;
        self.cursor_y += dy;
        self.clamp_cursor(layout);
        self.refresh_hover(layout);
    }

    /// Absolute pointer position (tablet).
    pub fn move_abs(&mut self, layout: &ShellLayout, x: i32, y: i32) {
        self.cursor_x = x;
        self.cursor_y = y;
        self.clamp_cursor(layout);
        self.refresh_hover(layout);
    }

    pub fn refresh_hover(&mut self, layout: &ShellLayout) {
        self.hover_dock = hit_test_dock(layout, self.cursor_x, self.cursor_y);
        if self.launcher_open {
            let ll = LauncherLayout::for_shell(layout);
            if let Some(c) = ll.hit_category(self.cursor_x, self.cursor_y) {
                self.launcher_focus = c;
            }
        }
    }

    /// Primary click (press). First dock icon toggles Launcher; close button / Esc.
    pub fn on_primary_press(&mut self, layout: &ShellLayout) {
        self.left_down = true;
        let ll = LauncherLayout::for_shell(layout);
        if self.launcher_open {
            if ll.hit_close(self.cursor_x, self.cursor_y) {
                self.close_launcher();
                return;
            }
            if let Some(c) = ll.hit_category(self.cursor_x, self.cursor_y) {
                self.launcher_focus = c;
                // Illustrative select only — no app exec.
                return;
            }
            if !ll.contains(self.cursor_x, self.cursor_y) {
                // Click outside launcher closes it (unless on dock icon 0 toggle).
                if hit_test_dock(layout, self.cursor_x, self.cursor_y) != Some(0) {
                    self.close_launcher();
                }
            }
        }
        if let Some(idx) = hit_test_dock(layout, self.cursor_x, self.cursor_y) {
            self.selected_dock = Some(idx);
            if idx == 0 {
                self.launcher_open = !self.launcher_open;
                if self.launcher_open {
                    self.launcher_focus = 0;
                }
            }
        }
    }

    pub fn on_primary_release(&mut self) {
        self.left_down = false;
    }

    /// Close launcher (Esc / close control).
    pub fn close_launcher(&mut self) {
        self.launcher_open = false;
    }

    pub fn open_launcher(&mut self) {
        self.launcher_open = true;
        self.launcher_focus = 0;
    }

    /// Keyboard dock navigation when launcher closed.
    pub fn nav_dock(&mut self, layout: &ShellLayout, delta: i32) {
        let cur = self.selected_dock.or(self.hover_dock).unwrap_or(0) as i32;
        let next = (cur + delta).rem_euclid(DOCK_SLOTS as i32) as usize;
        self.selected_dock = Some(next);
        self.hover_dock = Some(next);
        if let Some((ix, iy, w, h)) = layout.dock_icon_rect(next) {
            self.cursor_x = ix + w / 2;
            self.cursor_y = iy + h / 2;
        }
    }

    /// Keyboard category navigation when launcher open.
    pub fn nav_launcher(&mut self, delta: i32) {
        let n = LAUNCHER_CATEGORIES.len() as i32;
        let cur = self.launcher_focus as i32;
        self.launcher_focus = (cur + delta).rem_euclid(n) as usize;
    }

    pub fn activate_selected(&mut self) {
        if self.launcher_open {
            // Focus stays; illustrative — no exec.
            return;
        }
        if self.selected_dock == Some(0) {
            self.open_launcher();
        }
    }
}

/// Hit-test dock icons. Returns slot index or `None`.
#[must_use]
pub fn hit_test_dock(layout: &ShellLayout, x: i32, y: i32) -> Option<usize> {
    for i in 0..DOCK_SLOTS {
        if let Some((ix, iy, w, h)) = layout.dock_icon_rect(i) {
            if x >= ix && x < ix + w && y >= iy && y < iy + h {
                return Some(i);
            }
        }
    }
    None
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
        'B' => Some([0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E]),
        'C' => Some([0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E]),
        'D' => Some([0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E]),
        'E' => Some([0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F]),
        'F' => Some([0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10]),
        'G' => Some([0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F]),
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
        'X' => Some([0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11]),
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

/// Draw a simple cursor (arrow-ish) at FB coordinates — clipped.
pub fn draw_cursor(buf: &mut RgbBuffer, x: i32, y: i32) {
    // 11×15 pointer silhouette (white + navy outline).
    const ROWS: &[&[u8]] = &[
        b"10000000000",
        b"11000000000",
        b"12100000000",
        b"12210000000",
        b"12221000000",
        b"12222100000",
        b"12222210000",
        b"12222221000",
        b"12222222100",
        b"12222111110",
        b"12122100000",
        b"11012210000",
        b"10001210000",
        b"00001221000",
        b"00000110000",
    ];
    for (row_i, row) in ROWS.iter().enumerate() {
        for (col_i, ch) in row.iter().enumerate() {
            let rgb = match ch {
                b'1' => COLOR_NAVY_DEEP,
                b'2' => COLOR_TEXT,
                _ => continue,
            };
            put(buf, x + col_i as i32, y + row_i as i32, rgb);
        }
    }
}

/// Compose the full shell chrome into `buf` (must already match layout size).
pub fn compose_shell(buf: &mut RgbBuffer, layout: &ShellLayout) {
    compose_shell_interactive(buf, layout, None);
}

/// Compose chrome + optional interactive overlays (cursor / hover / launcher).
pub fn compose_shell_interactive(
    buf: &mut RgbBuffer,
    layout: &ShellLayout,
    ui: Option<&InteractiveState>,
) {
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
    // Status (right) — fact-based indicator only (never auto PASS_MANUAL).
    let status = ui
        .map(|u| u.input_fact.panel_label())
        .unwrap_or("INPUT UNAVAILABLE");
    let status_scale = if layout.width >= 900 { text_scale } else { 1 };
    let status_w = status.len() as i32 * 6 * status_scale;
    draw_text(
        buf,
        layout.width as i32 - status_w - 12,
        8,
        status,
        status_scale,
        COLOR_MUTED,
    );

    // Desktop hint card (illustrative) — hidden while launcher open.
    if layout.desktop_h > 80 && !ui.is_some_and(|u| u.launcher_open) {
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
            "LAUNCHER 015.2",
            text_scale,
            COLOR_MUTED,
        );
    }

    // Ryoku Launcher panel — title / categories / focus / close (adaptive).
    if let Some(u) = ui.filter(|u| u.launcher_open) {
        let ll = LauncherLayout::for_shell(layout);
        fill_rounded(buf, ll.x, ll.y, ll.w, ll.h, 12, COLOR_PANEL);
        fill_rect(buf, ll.x, ll.y, ll.w, 3, COLOR_TEAL);
        draw_text(
            buf,
            ll.x + 14,
            ll.y + 12,
            "RYOKU LAUNCHER",
            text_scale,
            COLOR_TEAL,
        );
        // Close control
        fill_rounded(
            buf,
            ll.close_x,
            ll.close_y,
            ll.close_s,
            ll.close_s,
            4,
            COLOR_TEAL_DIM,
        );
        draw_text(buf, ll.close_x + 4, ll.close_y + 4, "X", 1, COLOR_TEXT);
        draw_text(
            buf,
            ll.x + 14,
            ll.y + 12 + 10 * text_scale + 4,
            "NO APP EXEC - ESC CLOSES",
            1,
            COLOR_MUTED,
        );
        for (i, cat) in LAUNCHER_CATEGORIES.iter().enumerate() {
            let ry = ll.row_y0 + (i as i32) * ll.row_h;
            let focused = u.launcher_focus == i;
            if focused {
                fill_rounded(
                    buf,
                    ll.x + 10,
                    ry - 2,
                    ll.w - 20,
                    ll.row_h - 4,
                    6,
                    COLOR_TEAL_DIM,
                );
            }
            draw_text(
                buf,
                ll.x + 18,
                ry + 4,
                cat,
                1,
                if focused { COLOR_TEXT } else { COLOR_MUTED },
            );
        }
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
    for i in 0..DOCK_SLOTS {
        let Some((ix, iy, icon, _)) = layout.dock_icon_rect(i) else {
            continue;
        };
        let hovered = ui.and_then(|u| u.hover_dock) == Some(i);
        let selected = ui.and_then(|u| u.selected_dock) == Some(i);
        if hovered || selected {
            fill_rounded(
                buf,
                ix - 3,
                iy - 3,
                icon + 6,
                icon + 6,
                8,
                if selected { COLOR_TEAL } else { COLOR_TEAL_DIM },
            );
        }
        let accent = if i == 0 { COLOR_TEAL } else { COLOR_TEAL_DIM };
        draw_icon(buf, ix, iy, icon, accent);
    }

    if let Some(u) = ui {
        draw_cursor(buf, u.cursor_x, u.cursor_y);
    }
}

/// Build an RGB software buffer with the shell layout for the given FB size.
pub fn render_shell(width: u32, height: u32) -> Result<(RgbBuffer, ShellLayout), String> {
    let layout = ShellLayout::for_fb(width, height)?;
    let mut buf = RgbBuffer::new(layout.width, layout.height, COLOR_NAVY);
    compose_shell(&mut buf, &layout);
    Ok((buf, layout))
}

/// Render with interactive overlays.
pub fn render_shell_interactive(
    width: u32,
    height: u32,
    ui: &InteractiveState,
) -> Result<(RgbBuffer, ShellLayout), String> {
    let layout = ShellLayout::for_fb(width, height)?;
    let mut buf = RgbBuffer::new(layout.width, layout.height, COLOR_NAVY);
    compose_shell_interactive(&mut buf, &layout, Some(ui));
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

    #[test]
    fn dock_hit_test_first_icon() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        let (ix, iy, w, h) = l.dock_icon_rect(0).unwrap();
        assert_eq!(hit_test_dock(&l, ix + w / 2, iy + h / 2), Some(0));
        assert_eq!(hit_test_dock(&l, 0, 0), None);
    }

    #[test]
    fn launcher_opens_on_first_icon_click() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        let mut ui = InteractiveState::new(&l);
        let (ix, iy, w, h) = l.dock_icon_rect(0).unwrap();
        ui.move_abs(&l, ix + w / 2, iy + h / 2);
        ui.on_primary_press(&l);
        assert!(ui.launcher_open);
        ui.close_launcher();
        assert!(!ui.launcher_open);
    }

    #[test]
    fn launcher_close_button_hits() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        let mut ui = InteractiveState::new(&l);
        ui.open_launcher();
        let ll = LauncherLayout::for_shell(&l);
        ui.move_abs(&l, ll.close_x + 2, ll.close_y + 2);
        ui.on_primary_press(&l);
        assert!(!ui.launcher_open);
    }

    #[test]
    fn launcher_category_nav_wraps() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        let mut ui = InteractiveState::new(&l);
        ui.open_launcher();
        ui.nav_launcher(-1);
        assert_eq!(ui.launcher_focus, LAUNCHER_CATEGORIES.len() - 1);
        ui.nav_launcher(1);
        assert_eq!(ui.launcher_focus, 0);
    }

    #[test]
    fn input_fact_never_claims_pass_manual() {
        for f in [
            InputFact::Unavailable,
            InputFact::Detected,
            InputFact::EventsReceived,
        ] {
            assert!(!f.panel_label().contains("PASS"));
            assert!(!f.panel_label().contains("NOT_RUN"));
        }
        let mut f = InputFact::Detected;
        f.note_event();
        assert_eq!(f, InputFact::EventsReceived);
    }

    #[test]
    fn keyboard_nav_wraps_dock() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        let mut ui = InteractiveState::new(&l);
        ui.selected_dock = Some(0);
        ui.nav_dock(&l, -1);
        assert_eq!(ui.selected_dock, Some(DOCK_SLOTS - 1));
    }

    #[test]
    fn cursor_clamped_to_fb() {
        let l = ShellLayout::for_fb(320, 240).unwrap();
        let mut ui = InteractiveState::new(&l);
        ui.move_by(&l, 10_000, 10_000);
        assert!(ui.cursor_x < 320);
        assert!(ui.cursor_y < 240);
    }
}
