//! Mission 017 — Internal Window System (geometry, focus, z-order, dirty regions).
//!
//! Windows are **in-process** Rust chrome only — no external app exec, no Wayland
//! compositor claim. Guest PASS is manual only (`GUEST_NOT_RUN` until human).

use crate::{draw_text, fill_rect, AdaptiveProfile, COLOR_MUTED, COLOR_TEAL, COLOR_TEXT};

/// Opaque window handle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WindowId(pub u32);

/// Axis-aligned rectangle in FB coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    #[must_use]
    pub fn new(x: i32, y: i32, w: i32, h: i32) -> Self {
        Self { x, y, w, h }
    }

    #[must_use]
    pub fn contains(self, px: i32, py: i32) -> bool {
        px >= self.x && py >= self.y && px < self.x + self.w && py < self.y + self.h
    }

    #[must_use]
    pub fn intersect(self, other: Self) -> Option<Self> {
        let x0 = self.x.max(other.x);
        let y0 = self.y.max(other.y);
        let x1 = (self.x + self.w).min(other.x + other.w);
        let y1 = (self.y + self.h).min(other.y + other.h);
        if x1 > x0 && y1 > y0 {
            Some(Self::new(x0, y0, x1 - x0, y1 - y0))
        } else {
            None
        }
    }

    #[must_use]
    pub fn union(self, other: Self) -> Self {
        if self.w <= 0 || self.h <= 0 {
            return other;
        }
        if other.w <= 0 || other.h <= 0 {
            return self;
        }
        let x0 = self.x.min(other.x);
        let y0 = self.y.min(other.y);
        let x1 = (self.x + self.w).max(other.x + other.w);
        let y1 = (self.y + self.h).max(other.y + other.h);
        Self::new(x0, y0, x1 - x0, y1 - y0)
    }

    #[must_use]
    pub fn y_band(self) -> (u32, u32) {
        let y0 = self.y.max(0) as u32;
        let y1 = (self.y + self.h).max(0) as u32;
        (y0, y1.max(y0))
    }

    #[must_use]
    pub fn clamp_to(self, bounds: Self) -> Self {
        let x = self
            .x
            .clamp(bounds.x, bounds.x + bounds.w.saturating_sub(1));
        let y = self
            .y
            .clamp(bounds.y, bounds.y + bounds.h.saturating_sub(1));
        let w = self.w.clamp(MIN_WIN_W, bounds.w);
        let h = self.h.clamp(MIN_WIN_H, bounds.h);
        let x = x.min(bounds.x + bounds.w - w);
        let y = y.min(bounds.y + bounds.h - h);
        Self::new(x.max(bounds.x), y.max(bounds.y), w, h)
    }
}

pub const TITLEBAR_H: i32 = 22;
pub const MIN_WIN_W: i32 = 160;
pub const MIN_WIN_H: i32 = 80;
pub const RESIZE_EDGE: i32 = 6;

/// Window lifecycle (Mission 017 foundation; fully exercised in 019).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WindowLifecycle {
    #[default]
    Created,
    Visible,
    Focused,
    Minimized,
    Closed,
}

/// Kind of internal content (018 fills real apps; 017 uses Demo).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WindowKind {
    #[default]
    Demo,
    About,
    SystemMonitor,
    Settings,
    FilesRo,
}

impl WindowKind {
    #[must_use]
    pub fn title(self) -> &'static str {
        match self {
            Self::Demo => "WM DEMO",
            Self::About => "ABOUT RYOKU",
            Self::SystemMonitor => "SYSTEM MONITOR",
            Self::Settings => "SETTINGS",
            Self::FilesRo => "FILES RO",
        }
    }

    #[must_use]
    pub fn allowlisted(self) -> bool {
        // All kinds are internal allowlist members — never arbitrary exec.
        true
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Window {
    pub id: WindowId,
    pub kind: WindowKind,
    pub title: String,
    pub geom: Rect,
    pub restore: Rect,
    pub lifecycle: WindowLifecycle,
    pub maximized: bool,
}

impl Window {
    #[must_use]
    pub fn titlebar(&self) -> Rect {
        Rect::new(self.geom.x, self.geom.y, self.geom.w, TITLEBAR_H)
    }

    #[must_use]
    pub fn client(&self) -> Rect {
        Rect::new(
            self.geom.x,
            self.geom.y + TITLEBAR_H,
            self.geom.w,
            (self.geom.h - TITLEBAR_H).max(0),
        )
    }

    #[must_use]
    pub fn close_hit(&self) -> Rect {
        Rect::new(self.geom.x + self.geom.w - 20, self.geom.y + 3, 16, 16)
    }

    #[must_use]
    pub fn max_hit(&self) -> Rect {
        Rect::new(self.geom.x + self.geom.w - 40, self.geom.y + 3, 16, 16)
    }

    #[must_use]
    pub fn min_hit(&self) -> Rect {
        Rect::new(self.geom.x + self.geom.w - 60, self.geom.y + 3, 16, 16)
    }

    #[must_use]
    pub fn visible(&self) -> bool {
        matches!(
            self.lifecycle,
            WindowLifecycle::Visible | WindowLifecycle::Focused
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum WmEvent {
    Created(WindowId),
    Focused(WindowId),
    Moved(WindowId),
    Resized(WindowId),
    Minimized(WindowId),
    Maximized(WindowId),
    Restored(WindowId),
    Closed(WindowId),
}

/// Hit region inside a window chrome.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WinHit {
    Client,
    Titlebar,
    Close,
    Minimize,
    Maximize,
    ResizeE,
    ResizeS,
    ResizeSe,
}

/// In-process window manager (no external compositor).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WindowManager {
    next_id: u32,
    windows: Vec<Window>,
    /// Bottom → top z-order (last = topmost).
    z_order: Vec<WindowId>,
    focus: Option<WindowId>,
    dirty: Option<Rect>,
    events: Vec<WmEvent>,
    desktop: Rect,
}

impl WindowManager {
    #[must_use]
    pub fn new(desktop: Rect) -> Self {
        Self {
            next_id: 1,
            windows: Vec::new(),
            z_order: Vec::new(),
            focus: None,
            dirty: None,
            events: Vec::new(),
            desktop,
        }
    }

    pub fn set_desktop(&mut self, desktop: Rect) {
        self.desktop = desktop;
    }

    #[must_use]
    pub fn focus(&self) -> Option<WindowId> {
        self.focus
    }

    #[must_use]
    pub fn windows(&self) -> &[Window] {
        &self.windows
    }

    #[must_use]
    pub fn z_order(&self) -> &[WindowId] {
        &self.z_order
    }

    pub fn take_events(&mut self) -> Vec<WmEvent> {
        core::mem::take(&mut self.events)
    }

    pub fn take_dirty(&mut self) -> Option<Rect> {
        self.dirty.take()
    }

    pub fn mark_dirty(&mut self, r: Rect) {
        self.dirty = Some(match self.dirty {
            Some(d) => d.union(r),
            None => r,
        });
    }

    fn push_event(&mut self, e: WmEvent) {
        self.events.push(e);
    }

    fn find_mut(&mut self, id: WindowId) -> Option<&mut Window> {
        self.windows.iter_mut().find(|w| w.id == id)
    }

    fn find(&self, id: WindowId) -> Option<&Window> {
        self.windows.iter().find(|w| w.id == id)
    }

    /// Create a visible focused window of `kind` (internal only).
    pub fn create(&mut self, kind: WindowKind, geom: Rect) -> WindowId {
        let id = WindowId(self.next_id);
        self.next_id = self.next_id.saturating_add(1);
        let geom = geom.clamp_to(self.desktop);
        let w = Window {
            id,
            kind,
            title: kind.title().to_string(),
            geom,
            restore: geom,
            lifecycle: WindowLifecycle::Focused,
            maximized: false,
        };
        self.mark_dirty(w.geom);
        self.windows.push(w);
        self.z_order.push(id);
        self.focus = Some(id);
        self.push_event(WmEvent::Created(id));
        self.push_event(WmEvent::Focused(id));
        id
    }

    pub fn focus_window(&mut self, id: WindowId) {
        if self.find(id).is_none() {
            return;
        }
        if let Some(prev) = self.focus {
            let mut dirty_prev = None;
            if let Some(w) = self.find_mut(prev) {
                if w.lifecycle == WindowLifecycle::Focused {
                    w.lifecycle = WindowLifecycle::Visible;
                    dirty_prev = Some(w.geom);
                }
            }
            if let Some(r) = dirty_prev {
                self.mark_dirty(r);
            }
        }
        self.z_order.retain(|z| *z != id);
        self.z_order.push(id);
        let mut dirty_id = None;
        if let Some(w) = self.find_mut(id) {
            w.lifecycle = WindowLifecycle::Focused;
            dirty_id = Some(w.geom);
        }
        if let Some(r) = dirty_id {
            self.mark_dirty(r);
        }
        self.focus = Some(id);
        self.push_event(WmEvent::Focused(id));
    }

    pub fn close(&mut self, id: WindowId) {
        let Some(idx) = self.windows.iter().position(|w| w.id == id) else {
            return;
        };
        let geom = self.windows[idx].geom;
        self.windows[idx].lifecycle = WindowLifecycle::Closed;
        self.mark_dirty(geom);
        self.windows.remove(idx);
        self.z_order.retain(|z| *z != id);
        if self.focus == Some(id) {
            self.focus = self.z_order.last().copied();
            if let Some(f) = self.focus {
                self.focus_window(f);
            }
        }
        self.push_event(WmEvent::Closed(id));
    }

    pub fn minimize(&mut self, id: WindowId) {
        let mut dirty = None;
        if let Some(w) = self.find_mut(id) {
            w.lifecycle = WindowLifecycle::Minimized;
            dirty = Some(w.geom);
        }
        if let Some(r) = dirty {
            self.mark_dirty(r);
            self.push_event(WmEvent::Minimized(id));
        }
        if self.focus == Some(id) {
            self.focus = None;
            if let Some(&top) = self.z_order.iter().rev().find(|&&z| {
                self.find(z)
                    .is_some_and(|w| w.lifecycle != WindowLifecycle::Minimized)
            }) {
                self.focus_window(top);
            }
        }
    }

    pub fn maximize_toggle(&mut self, id: WindowId) {
        let desktop = self.desktop;
        let Some(w) = self.find_mut(id) else {
            return;
        };
        if w.maximized {
            w.geom = w.restore;
            w.maximized = false;
            self.mark_dirty(desktop);
            self.push_event(WmEvent::Restored(id));
        } else {
            w.restore = w.geom;
            w.geom = desktop;
            w.maximized = true;
            self.mark_dirty(desktop);
            self.push_event(WmEvent::Maximized(id));
        }
        self.focus_window(id);
    }

    pub fn move_by(&mut self, id: WindowId, dx: i32, dy: i32) {
        let desktop = self.desktop;
        let dirty = {
            let Some(w) = self.find_mut(id) else {
                return;
            };
            if w.maximized {
                return;
            }
            let old = w.geom;
            w.geom.x += dx;
            w.geom.y += dy;
            w.geom = w.geom.clamp_to(desktop);
            old.union(w.geom)
        };
        self.mark_dirty(dirty);
        self.push_event(WmEvent::Moved(id));
    }

    pub fn resize_by(&mut self, id: WindowId, dw: i32, dh: i32) {
        let desktop = self.desktop;
        let dirty = {
            let Some(w) = self.find_mut(id) else {
                return;
            };
            if w.maximized {
                return;
            }
            let old = w.geom;
            w.geom.w = (w.geom.w + dw).max(MIN_WIN_W);
            w.geom.h = (w.geom.h + dh).max(MIN_WIN_H);
            w.geom = w.geom.clamp_to(desktop);
            old.union(w.geom)
        };
        self.mark_dirty(dirty);
        self.push_event(WmEvent::Resized(id));
    }

    /// Hit-test topmost visible window under point.
    #[must_use]
    pub fn hit_test(&self, px: i32, py: i32) -> Option<(WindowId, WinHit)> {
        for &id in self.z_order.iter().rev() {
            let Some(w) = self.find(id) else {
                continue;
            };
            if matches!(
                w.lifecycle,
                WindowLifecycle::Closed | WindowLifecycle::Minimized | WindowLifecycle::Created
            ) {
                continue;
            }
            if !w.geom.contains(px, py) {
                continue;
            }
            if w.close_hit().contains(px, py) {
                return Some((id, WinHit::Close));
            }
            if w.max_hit().contains(px, py) {
                return Some((id, WinHit::Maximize));
            }
            if w.min_hit().contains(px, py) {
                return Some((id, WinHit::Minimize));
            }
            if w.titlebar().contains(px, py) {
                return Some((id, WinHit::Titlebar));
            }
            let right = px >= w.geom.x + w.geom.w - RESIZE_EDGE;
            let bottom = py >= w.geom.y + w.geom.h - RESIZE_EDGE;
            if right && bottom {
                return Some((id, WinHit::ResizeSe));
            }
            if right {
                return Some((id, WinHit::ResizeE));
            }
            if bottom {
                return Some((id, WinHit::ResizeS));
            }
            return Some((id, WinHit::Client));
        }
        None
    }

    /// Paint all visible windows bottom→top into `buf` (no fb clear).
    pub fn compose(&self, buf: &mut ryoku_graphics_demo::RgbBuffer, profile: AdaptiveProfile) {
        let theme = profile.theme();
        for &id in &self.z_order {
            let Some(w) = self.find(id) else {
                continue;
            };
            if matches!(
                w.lifecycle,
                WindowLifecycle::Closed | WindowLifecycle::Minimized | WindowLifecycle::Created
            ) {
                continue;
            }
            paint_window(buf, w, self.focus == Some(id), &theme);
        }
    }
}

fn paint_window(
    buf: &mut ryoku_graphics_demo::RgbBuffer,
    w: &Window,
    focused: bool,
    theme: &crate::ProfileTheme,
) {
    let border = if focused { theme.teal } else { theme.teal_dim };
    fill_rect(buf, w.geom.x, w.geom.y, w.geom.w, w.geom.h, theme.panel);
    fill_rect(buf, w.geom.x, w.geom.y, w.geom.w, 2, border);
    fill_rect(
        buf,
        w.geom.x,
        w.geom.y,
        w.geom.w,
        TITLEBAR_H,
        if focused { theme.navy } else { theme.dock },
    );
    draw_text(
        buf,
        w.geom.x + 8,
        w.geom.y + 6,
        &w.title,
        1,
        if focused { COLOR_TEAL } else { COLOR_MUTED },
    );
    // Chrome buttons: _ □ X
    draw_text(
        buf,
        w.min_hit().x + 4,
        w.min_hit().y + 4,
        "-",
        1,
        COLOR_TEXT,
    );
    draw_text(
        buf,
        w.max_hit().x + 3,
        w.max_hit().y + 4,
        "O",
        1,
        COLOR_TEXT,
    );
    draw_text(
        buf,
        w.close_hit().x + 4,
        w.close_hit().y + 4,
        "X",
        1,
        COLOR_TEXT,
    );

    let client = w.client();
    let lines: [&str; 3] = match w.kind {
        WindowKind::Demo => [
            "INTERNAL WINDOW - NO EXT APP",
            "DIRTY REGIONS - NO FB CLEAR",
            "LAUNCHER OPENS ALLOWLIST APPS",
        ],
        WindowKind::About => [
            "RYOKU MINIMAL LAB SHELL",
            "NOT A PRODUCT OS BOOT",
            "NO WAYLAND / NO BLUR / NO 3D",
        ],
        WindowKind::SystemMonitor => [
            "ILLUSTRATIVE METRICS ONLY",
            "NO /PROC LIVE PROBES HERE",
            "SEE HW CONSOLE FOR FACTS",
        ],
        WindowKind::Settings => [
            "PROFILE VIA F1 F2 F3",
            "NO PERSISTENCE STORE",
            "ULTRA = ARCH FALLBACK",
        ],
        WindowKind::FilesRo => [
            "READ-ONLY FILE LIST DEMO",
            "/bin /dev /proc ILLUSTRATIVE",
            "NO EXEC / NO WRITE",
        ],
    };
    for (i, line) in lines.iter().enumerate() {
        draw_text(
            buf,
            client.x + 10,
            client.y + 12 + (i as i32) * 16,
            line,
            1,
            if i == 0 { COLOR_TEXT } else { COLOR_MUTED },
        );
    }
}

/// Desktop work area below panel / above dock.
#[must_use]
pub fn desktop_work_area(panel_h: u32, dock_y: u32, width: u32, height: u32) -> Rect {
    let y = panel_h as i32;
    let h = (dock_y.saturating_sub(panel_h)).max(MIN_WIN_H as u32) as i32;
    Rect::new(0, y, width as i32, h.min(height as i32 - y))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn desk() -> Rect {
        Rect::new(0, 28, 640, 400)
    }

    #[test]
    fn create_focus_zorder_close() {
        let mut wm = WindowManager::new(desk());
        let a = wm.create(WindowKind::Demo, Rect::new(40, 40, 200, 120));
        let b = wm.create(WindowKind::Demo, Rect::new(80, 60, 200, 120));
        assert_eq!(wm.focus(), Some(b));
        assert_eq!(*wm.z_order().last().unwrap(), b);
        wm.focus_window(a);
        assert_eq!(wm.focus(), Some(a));
        assert_eq!(*wm.z_order().last().unwrap(), a);
        wm.close(a);
        assert!(wm.find(a).is_none());
        assert_eq!(wm.focus(), Some(b));
    }

    #[test]
    fn move_resize_min_max_dirty() {
        let mut wm = WindowManager::new(desk());
        let id = wm.create(WindowKind::Demo, Rect::new(50, 50, 220, 140));
        let _ = wm.take_dirty();
        wm.move_by(id, 10, 5);
        assert!(wm.take_dirty().is_some());
        wm.resize_by(id, 20, 10);
        let w = wm.find(id).unwrap();
        assert!(w.geom.w >= 220);
        wm.minimize(id);
        assert_eq!(wm.find(id).unwrap().lifecycle, WindowLifecycle::Minimized);
        wm.focus_window(id);
        wm.maximize_toggle(id);
        assert!(wm.find(id).unwrap().maximized);
        wm.maximize_toggle(id);
        assert!(!wm.find(id).unwrap().maximized);
    }

    #[test]
    fn hit_test_topmost() {
        let mut wm = WindowManager::new(desk());
        let _a = wm.create(WindowKind::Demo, Rect::new(40, 40, 200, 120));
        let b = wm.create(WindowKind::Demo, Rect::new(60, 50, 200, 120));
        let (id, hit) = wm.hit_test(70, 55).unwrap();
        assert_eq!(id, b);
        assert_eq!(hit, WinHit::Titlebar);
    }

    #[test]
    fn no_external_exec_kinds() {
        for k in [
            WindowKind::Demo,
            WindowKind::About,
            WindowKind::SystemMonitor,
            WindowKind::Settings,
            WindowKind::FilesRo,
        ] {
            assert!(k.allowlisted());
            assert!(!k.title().contains("EXEC"));
        }
    }

    #[test]
    fn rect_union_intersect() {
        let a = Rect::new(0, 0, 10, 10);
        let b = Rect::new(5, 5, 10, 10);
        assert_eq!(a.intersect(b).unwrap(), Rect::new(5, 5, 5, 5));
        assert_eq!(a.union(b), Rect::new(0, 0, 15, 15));
    }
}
