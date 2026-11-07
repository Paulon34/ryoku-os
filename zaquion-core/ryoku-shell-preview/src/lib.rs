//! Ryoku Shell Preview — illustrative desktop layout (Mission 015–**017**).
//!
//! Draws a navy/teal top panel, desktop area, dock, and status into an RGB888
//! software buffer. Presentation to `/dev/fb0` reuses Mission 014.2 validation
//! (`ryoku-graphics-demo`).
//!
//! Mission **016** adaptive profiles; **016.1** perf metrics; **016.2** controlled
//! benchmark (opt-in). Mission **017** adds an in-process WindowManager (geometry,
//! focus, z-order, dirty regions) — no external apps, no Wayland compositor claim.
//! QEMU TCG ≠ hardware. This crate **never** invents `PASS_MANUAL` from CI.

#![forbid(unsafe_code)]

mod adaptive;
mod benchmark;
mod perf;
mod window;

pub use adaptive::{AdaptiveProfile, ProfileTheme, RenderPolicy};
pub use benchmark::{
    controlled_band, controlled_benchmark_enabled, controlled_profile_order,
    instrumentation_cost_note, ControlledProfileRun, ControlledSummary, CONTROLLED_BAND_FRAMES,
    CONTROLLED_FULL_FRAMES,
};
pub use perf::{
    ultra_slowdown_investigation, FrameAccumulator, FrameSample, PerfOverlayPolicy, ProfileCompare,
};
pub use window::{
    desktop_work_area, Rect, WinHit, WindowId, WindowKind, WindowLifecycle, WindowManager, WmEvent,
};

use ryoku_graphics_demo::{blit_rgb_to_fb, blit_rgb_to_fb_rows, FbGeometry, RgbBuffer};

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

/// Interactive UI state (Mission 015–017). Guest PASS is manual only.
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
    /// Mission 016 adaptive profile (session-switchable).
    pub profile: AdaptiveProfile,
    /// Mission 017 in-process window manager.
    pub wm: WindowManager,
    /// Drag/resize gesture state (expanded in 019).
    pub drag: Option<(WindowId, WinHit, i32, i32)>,
}

impl InteractiveState {
    #[must_use]
    pub fn new(layout: &ShellLayout) -> Self {
        let desktop = desktop_work_area(layout.panel_h, layout.dock_y, layout.width, layout.height);
        Self {
            cursor_x: (layout.width / 2) as i32,
            cursor_y: (layout.height / 2) as i32,
            hover_dock: None,
            selected_dock: None,
            launcher_open: false,
            launcher_focus: 0,
            left_down: false,
            input_fact: InputFact::Unavailable,
            profile: AdaptiveProfile::Balanced,
            wm: WindowManager::new(desktop),
            drag: None,
        }
    }

    pub fn set_profile(&mut self, profile: AdaptiveProfile) {
        self.profile = profile;
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

    /// Primary click (press). WM chrome first; then launcher/dock.
    pub fn on_primary_press(&mut self, layout: &ShellLayout) {
        self.left_down = true;
        // Mission 017: window chrome / focus before launcher.
        if let Some((id, hit)) = self.wm.hit_test(self.cursor_x, self.cursor_y) {
            self.wm.focus_window(id);
            match hit {
                WinHit::Close => self.wm.close(id),
                WinHit::Minimize => self.wm.minimize(id),
                WinHit::Maximize => self.wm.maximize_toggle(id),
                WinHit::Titlebar | WinHit::ResizeE | WinHit::ResizeS | WinHit::ResizeSe => {
                    self.drag = Some((id, hit, self.cursor_x, self.cursor_y));
                }
                WinHit::Client => {}
            }
            return;
        }
        let ll = LauncherLayout::for_shell(layout);
        if self.launcher_open {
            if ll.hit_close(self.cursor_x, self.cursor_y) {
                self.close_launcher();
                return;
            }
            if let Some(c) = ll.hit_category(self.cursor_x, self.cursor_y) {
                self.launcher_focus = c;
                // 017: SYSTEM opens WM demo window (no external exec).
                if c == 0 {
                    self.open_demo_window(layout);
                    self.close_launcher();
                }
                return;
            }
            if !ll.contains(self.cursor_x, self.cursor_y)
                && hit_test_dock(layout, self.cursor_x, self.cursor_y) != Some(0)
            {
                self.close_launcher();
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
        self.drag = None;
    }

    /// Open an internal demo window (Mission 017 — no external app).
    pub fn open_demo_window(&mut self, layout: &ShellLayout) {
        let desk = desktop_work_area(layout.panel_h, layout.dock_y, layout.width, layout.height);
        self.wm.set_desktop(desk);
        let n = self.wm.windows().len() as i32;
        let geom = Rect::new(40 + n * 24, desk.y + 20 + n * 16, 280, 160);
        self.wm.create(WindowKind::Demo, geom);
    }

    /// Pointer motion while dragging title/resize (017 basic; 019 expands).
    pub fn on_drag_motion(&mut self, x: i32, y: i32) {
        let Some((id, hit, ox, oy)) = self.drag else {
            return;
        };
        let dx = x - ox;
        let dy = y - oy;
        match hit {
            WinHit::Titlebar => self.wm.move_by(id, dx, dy),
            WinHit::ResizeE => self.wm.resize_by(id, dx, 0),
            WinHit::ResizeS => self.wm.resize_by(id, 0, dy),
            WinHit::ResizeSe => self.wm.resize_by(id, dx, dy),
            _ => {}
        }
        self.drag = Some((id, hit, x, y));
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

    pub fn activate_selected(&mut self, layout: &ShellLayout) {
        if self.launcher_open {
            if self.launcher_focus == 0 {
                self.open_demo_window(layout);
                self.close_launcher();
            }
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
        '3' => Some([0x1F, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1F]),
        '4' => Some([0x11, 0x11, 0x11, 0x1F, 0x01, 0x01, 0x01]),
        '5' => Some([0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E]),
        '6' => Some([0x0E, 0x10, 0x10, 0x1E, 0x11, 0x11, 0x0E]),
        '7' => Some([0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08]),
        '8' => Some([0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E]),
        '9' => Some([0x0E, 0x11, 0x11, 0x0F, 0x01, 0x01, 0x0E]),
        '=' => Some([0x00, 0x1F, 0x00, 0x1F, 0x00, 0x00, 0x00]),
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
    let profile = ui.map(|u| u.profile).unwrap_or_default();
    let theme = profile.theme();

    // Desktop wallpaper — Lite solid; Balanced/Ultra-effective gradient (no blur).
    if profile.use_gradient_wallpaper() {
        for y in 0..buf.height {
            let t = y * 255 / buf.height.max(1);
            let r = theme.navy.0 as u32
                + (theme.navy_deep.0 as u32).saturating_sub(theme.navy.0 as u32) * t / 255;
            let g = theme.navy.1 as u32 * (255 - t) / 255 + theme.navy_deep.1 as u32 * t / 255;
            let b = theme.navy.2 as u32 * (255 - t) / 255 + theme.teal_dim.2 as u32 * t / 400;
            fill_rect(
                buf,
                0,
                y as i32,
                buf.width as i32,
                1,
                (r as u8, g as u8, b.min(255) as u8),
            );
        }
    } else {
        fill_rect(
            buf,
            0,
            0,
            layout.width as i32,
            layout.height as i32,
            theme.navy,
        );
    }

    // Top panel
    fill_rect(
        buf,
        0,
        0,
        layout.width as i32,
        layout.panel_h as i32,
        theme.panel,
    );
    fill_rect(
        buf,
        0,
        layout.panel_h as i32 - 2,
        layout.width as i32,
        2,
        theme.teal_dim,
    );
    let text_scale = if layout.width >= 800 { 2 } else { 1 };
    draw_text(buf, 12, 8, "RYOKU", text_scale, theme.teal);
    let title = if matches!(profile, AdaptiveProfile::Ultra) {
        "ULTRA ARCH"
    } else {
        "SHELL PREVIEW"
    };
    draw_text(
        buf,
        12 + 6 * 5 * text_scale + 8,
        8,
        title,
        text_scale,
        theme.text,
    );
    // Left-mid: profile tag (Mission 016).
    let ptag = profile.panel_tag();
    draw_text(buf, 12 + 6 * 18 * text_scale + 16, 8, ptag, 1, theme.muted);
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
        theme.muted,
    );

    // Desktop hint card — Balanced only; hidden while launcher open.
    if profile.show_hint_card() && layout.desktop_h > 80 && !ui.is_some_and(|u| u.launcher_open) {
        let card_w = (layout.width as i32 * 45 / 100).clamp(220, 420);
        let card_h = (layout.desktop_h as i32 / 3).clamp(70, 120);
        let card_x = (layout.width as i32 - card_w) / 2;
        let card_y = layout.desktop_y as i32 + (layout.desktop_h as i32 - card_h) / 3;
        fill_rounded(buf, card_x, card_y, card_w, card_h, 10, theme.panel);
        draw_text(
            buf,
            card_x + 16,
            card_y + 18,
            "MINIMAL DEVELOPER PREVIEW",
            text_scale,
            theme.text,
        );
        draw_text(
            buf,
            card_x + 16,
            card_y + 18 + 10 * text_scale + 8,
            "ADAPTIVE 016 F1-F3",
            text_scale,
            theme.muted,
        );
    }

    // Ultra honesty strip (architecture only — paint is Balanced fallback).
    if matches!(profile, AdaptiveProfile::Ultra) && !ui.is_some_and(|u| u.launcher_open) {
        draw_text(
            buf,
            16,
            layout.desktop_y as i32 + 8,
            "ULTRA = ARCH ONLY - FALLBACK BALANCED - NO BLUR/3D/WAYLAND",
            1,
            theme.muted,
        );
    }

    // Mission 017 — in-process windows (under launcher modal; above wallpaper).
    if let Some(u) = ui {
        u.wm.compose(buf, profile);
    }

    // Ryoku Launcher panel — title / categories / focus / close.
    if let Some(u) = ui.filter(|u| u.launcher_open) {
        let ll = LauncherLayout::for_shell(layout);
        fill_rounded(buf, ll.x, ll.y, ll.w, ll.h, 12, theme.panel);
        fill_rect(buf, ll.x, ll.y, ll.w, 3, theme.teal);
        draw_text(
            buf,
            ll.x + 14,
            ll.y + 12,
            "RYOKU LAUNCHER",
            text_scale,
            theme.teal,
        );
        fill_rounded(
            buf,
            ll.close_x,
            ll.close_y,
            ll.close_s,
            ll.close_s,
            4,
            theme.teal_dim,
        );
        draw_text(buf, ll.close_x + 4, ll.close_y + 4, "X", 1, theme.text);
        draw_text(
            buf,
            ll.x + 14,
            ll.y + 12 + 10 * text_scale + 4,
            "NO APP EXEC - ESC CLOSES",
            1,
            theme.muted,
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
                    theme.teal_dim,
                );
            }
            draw_text(
                buf,
                ll.x + 18,
                ry + 4,
                cat,
                1,
                if focused { theme.text } else { theme.muted },
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
        theme.dock,
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
                if selected { theme.teal } else { theme.teal_dim },
            );
        }
        let accent = if i == 0 { theme.teal } else { theme.teal_dim };
        draw_icon_themed(buf, ix, iy, icon, accent, theme.panel);
    }

    if let Some(u) = ui {
        draw_cursor(buf, u.cursor_x, u.cursor_y);
    }
}

/// Compose only rows `[y0, y1)` into an existing scratch buffer.
///
/// Used for cursor-band dirty updates to avoid full-frame gradient work
/// (Mission 016.1). Caller must have a prior full compose when chrome changes.
pub fn compose_shell_band(
    buf: &mut RgbBuffer,
    layout: &ShellLayout,
    ui: &InteractiveState,
    y0: u32,
    y1: u32,
) {
    let y0 = y0.min(buf.height);
    let y1 = y1.min(buf.height).max(y0);
    if y1 <= y0 {
        return;
    }
    let profile = ui.profile;
    let theme = profile.theme();
    let band_h = (y1 - y0) as i32;

    if profile.use_gradient_wallpaper() {
        for y in y0..y1 {
            let t = y * 255 / buf.height.max(1);
            let r = theme.navy.0 as u32
                + (theme.navy_deep.0 as u32).saturating_sub(theme.navy.0 as u32) * t / 255;
            let g = theme.navy.1 as u32 * (255 - t) / 255 + theme.navy_deep.1 as u32 * t / 255;
            let b = theme.navy.2 as u32 * (255 - t) / 255 + theme.teal_dim.2 as u32 * t / 400;
            fill_rect(
                buf,
                0,
                y as i32,
                buf.width as i32,
                1,
                (r as u8, g as u8, b.min(255) as u8),
            );
        }
    } else {
        fill_rect(buf, 0, y0 as i32, layout.width as i32, band_h, theme.navy);
    }

    // Panel strip if band intersects.
    if y0 < layout.panel_h {
        let py1 = y1.min(layout.panel_h);
        fill_rect(
            buf,
            0,
            y0 as i32,
            layout.width as i32,
            (py1 - y0) as i32,
            theme.panel,
        );
        if y0 < 2 || py1 >= layout.panel_h.saturating_sub(2) {
            fill_rect(
                buf,
                0,
                layout.panel_h as i32 - 2,
                layout.width as i32,
                2,
                theme.teal_dim,
            );
        }
        if y0 < layout.panel_h {
            let text_scale = if layout.width >= 800 { 2 } else { 1 };
            draw_text(buf, 12, 8, "RYOKU", text_scale, theme.teal);
            let title = if matches!(profile, AdaptiveProfile::Ultra) {
                "ULTRA ARCH"
            } else {
                "SHELL PREVIEW"
            };
            draw_text(
                buf,
                12 + 6 * 5 * text_scale + 8,
                8,
                title,
                text_scale,
                theme.text,
            );
            draw_text(
                buf,
                12 + 6 * 18 * text_scale + 16,
                8,
                profile.panel_tag(),
                1,
                theme.muted,
            );
            let status = ui.input_fact.panel_label();
            let status_scale = if layout.width >= 900 { text_scale } else { 1 };
            let status_w = status.len() as i32 * 6 * status_scale;
            draw_text(
                buf,
                layout.width as i32 - status_w - 12,
                8,
                status,
                status_scale,
                theme.muted,
            );
        }
    }

    // Ultra honesty strip.
    if matches!(profile, AdaptiveProfile::Ultra) && !ui.launcher_open {
        let sy = layout.desktop_y as i32 + 8;
        if sy >= y0 as i32 && sy < y1 as i32 {
            draw_text(
                buf,
                16,
                sy,
                "ULTRA = ARCH ONLY - FALLBACK BALANCED - NO BLUR/3D/WAYLAND",
                1,
                theme.muted,
            );
        }
    }

    // Dock if band intersects dock vertical span.
    let dock_y0 = layout.dock_y;
    let dock_y1 = layout.dock_y + layout.dock_h;
    if y1 > dock_y0 && y0 < dock_y1 {
        fill_rounded(
            buf,
            layout.dock_x as i32,
            layout.dock_y as i32,
            layout.dock_w as i32,
            layout.dock_h as i32,
            12,
            theme.dock,
        );
        for i in 0..DOCK_SLOTS {
            let Some((ix, iy, icon, _)) = layout.dock_icon_rect(i) else {
                continue;
            };
            let hovered = ui.hover_dock == Some(i);
            let selected = ui.selected_dock == Some(i);
            if hovered || selected {
                fill_rounded(
                    buf,
                    ix - 3,
                    iy - 3,
                    icon + 6,
                    icon + 6,
                    8,
                    if selected { theme.teal } else { theme.teal_dim },
                );
            }
            let accent = if i == 0 { theme.teal } else { theme.teal_dim };
            draw_icon_themed(buf, ix, iy, icon, accent, theme.panel);
        }
    }

    draw_cursor(buf, ui.cursor_x, ui.cursor_y);
}

/// Draw optional perf overlay text (Mission 016.1; off-by-default policy).
pub fn draw_perf_overlay(buf: &mut RgbBuffer, layout: &ShellLayout, line: &str) {
    let y = (layout.panel_h as i32).saturating_sub(12).max(2);
    draw_text(buf, 12, y, line, 1, COLOR_MUTED);
}

fn draw_icon_themed(
    buf: &mut RgbBuffer,
    x: i32,
    y: i32,
    size: i32,
    accent: (u8, u8, u8),
    panel: (u8, u8, u8),
) {
    fill_rounded(buf, x, y, size, size, size / 5, panel);
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

/// Present shell buffer into an fb mmap (015.2.1: no visible clear; scanline copy).
pub fn present_shell(map: &mut [u8], geom: &FbGeometry, src: &RgbBuffer) -> Result<(), String> {
    blit_rgb_to_fb(map, geom, src).map_err(|e| format!("{SHELL_IDENTITY}: blit failed: {e}"))
}

/// Present only rows `[y0, y1)` (dirty region). Never clears; never past map.
pub fn present_shell_rows(
    map: &mut [u8],
    geom: &FbGeometry,
    src: &RgbBuffer,
    y0: u32,
    y1: u32,
) -> Result<(), String> {
    blit_rgb_to_fb_rows(map, geom, src, y0, y1)
        .map_err(|e| format!("{SHELL_IDENTITY}: blit rows failed: {e}"))
}

/// Expand a dirty Y band to cover a cursor-sized rect (11×15) plus padding.
#[must_use]
pub fn dirty_band_for_cursor(y: i32, height: u32) -> (u32, u32) {
    let y0 = (y - 2).max(0) as u32;
    let y1 = ((y + 17).max(0) as u32).min(height);
    (y0, y1.min(height).max(y0))
}

/// Merge two half-open Y bands.
#[must_use]
pub fn merge_dirty(a: (u32, u32), b: (u32, u32)) -> (u32, u32) {
    if a.0 >= a.1 {
        return b;
    }
    if b.0 >= b.1 {
        return a;
    }
    (a.0.min(b.0), a.1.max(b.1))
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

    #[test]
    fn compose_band_updates_cursor_rows_only() {
        let layout = ShellLayout::for_fb(320, 240).unwrap();
        let mut ui = InteractiveState::new(&layout);
        ui.set_profile(AdaptiveProfile::Balanced);
        ui.cursor_x = 40;
        ui.cursor_y = 120;
        let mut buf = RgbBuffer::new(layout.width, layout.height, COLOR_NAVY);
        compose_shell_interactive(&mut buf, &layout, Some(&ui));
        let before = buf.pixels.clone();
        ui.cursor_y = 130;
        compose_shell_band(&mut buf, &layout, &ui, 100, 150);
        let stride = (layout.width * 3) as usize;
        assert_eq!(&buf.pixels[..100 * stride], &before[..100 * stride]);
        assert_ne!(buf.pixels, before);
    }

    #[test]
    fn dirty_band_merge_and_cursor() {
        let a = dirty_band_for_cursor(100, 993);
        assert!(a.0 < a.1);
        assert!(a.1 <= 993);
        let b = dirty_band_for_cursor(200, 993);
        let m = merge_dirty(a, b);
        assert_eq!(m.0, a.0);
        assert_eq!(m.1, b.1);
        assert_eq!(merge_dirty((0, 0), a), a);
    }

    #[test]
    fn layout_paulo_941x993() {
        let l = ShellLayout::for_fb(941, 993).unwrap();
        assert_eq!(l.width, 941);
        assert!(l.dock_y + l.dock_h <= l.height);
    }

    #[test]
    fn adaptive_profile_switch_redraws_theme() {
        let l = ShellLayout::for_fb(941, 474).unwrap();
        let mut ui = InteractiveState::new(&l);
        ui.set_profile(AdaptiveProfile::Lite);
        let (buf_lite, _) = render_shell_interactive(941, 474, &ui).unwrap();
        ui.set_profile(AdaptiveProfile::Ultra);
        let (buf_ultra, _) = render_shell_interactive(941, 474, &ui).unwrap();
        // Different session labels / wallpaper policy → buffers differ.
        assert_ne!(buf_lite.pixels, buf_ultra.pixels);
        assert_eq!(ui.profile.effective(), AdaptiveProfile::Balanced);
    }
}
