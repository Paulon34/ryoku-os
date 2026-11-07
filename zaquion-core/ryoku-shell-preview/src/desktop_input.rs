//! Mission 019 — Desktop input policy & window lifecycle helpers.
//!
//! F1–F3 remain reserved for Adaptive profile switch (016). Desktop shortcuts
//! must not claim those keys. Guest PASS is manual only.

use crate::{WindowId, WindowLifecycle, WindowManager};

/// Keys reserved exclusively for Adaptive profile switching.
pub const RESERVED_PROFILE_KEYS: &[u16] = &[59, 60, 61]; // KEY_F1, KEY_F2, KEY_F3

/// Desktop shortcut ids (evdev codes) — disjoint from F1–F3.
pub const SHORTCUT_CLOSE_FOCUSED: u16 = 16; // KEY_Q
pub const SHORTCUT_CYCLE_FOCUS: u16 = 17; // KEY_W
pub const SHORTCUT_MINIMIZE: u16 = 50; // KEY_M

#[must_use]
pub fn is_reserved_profile_key(code: u16) -> bool {
    RESERVED_PROFILE_KEYS.contains(&code)
}

#[must_use]
pub fn is_desktop_shortcut(code: u16) -> bool {
    matches!(
        code,
        SHORTCUT_CLOSE_FOCUSED | SHORTCUT_CYCLE_FOCUS | SHORTCUT_MINIMIZE
    ) && !is_reserved_profile_key(code)
}

/// Cycle focus to the next visible (or minimized→focus) window in z-order.
pub fn cycle_focus(wm: &mut WindowManager) -> Option<WindowId> {
    let order: Vec<WindowId> = wm.z_order().to_vec();
    if order.is_empty() {
        return None;
    }
    let cur = wm.focus();
    let start = cur
        .and_then(|id| order.iter().position(|&x| x == id))
        .map(|i| (i + 1) % order.len())
        .unwrap_or(0);
    let id = order[start];
    wm.focus_window(id);
    Some(id)
}

/// Close the focused window if any.
pub fn close_focused(wm: &mut WindowManager) -> Option<WindowId> {
    let id = wm.focus()?;
    wm.close(id);
    Some(id)
}

/// Minimize the focused window if any.
pub fn minimize_focused(wm: &mut WindowManager) -> Option<WindowId> {
    let id = wm.focus()?;
    wm.minimize(id);
    Some(id)
}

/// Lifecycle transition helper (honesty: Created is unused after create→Focused).
#[must_use]
pub fn lifecycle_label(l: WindowLifecycle) -> &'static str {
    match l {
        WindowLifecycle::Created => "Created",
        WindowLifecycle::Visible => "Visible",
        WindowLifecycle::Focused => "Focused",
        WindowLifecycle::Minimized => "Minimized",
        WindowLifecycle::Closed => "Closed",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{desktop_work_area, Rect, WindowKind};

    #[test]
    fn shortcuts_do_not_conflict_f1_f3() {
        for code in RESERVED_PROFILE_KEYS {
            assert!(is_reserved_profile_key(*code));
            assert!(!is_desktop_shortcut(*code));
        }
        assert!(is_desktop_shortcut(SHORTCUT_CLOSE_FOCUSED));
        assert!(is_desktop_shortcut(SHORTCUT_CYCLE_FOCUS));
        assert!(is_desktop_shortcut(SHORTCUT_MINIMIZE));
    }

    #[test]
    fn cycle_and_close_lifecycle() {
        let desk = desktop_work_area(28, 400, 640, 480);
        let mut wm = WindowManager::new(desk);
        let a = wm.create(WindowKind::About, Rect::new(40, 40, 200, 120));
        let b = wm.create(WindowKind::Settings, Rect::new(80, 60, 200, 120));
        assert_eq!(wm.focus(), Some(b));
        cycle_focus(&mut wm);
        assert_eq!(wm.focus(), Some(a));
        minimize_focused(&mut wm);
        assert_eq!(
            wm.windows().iter().find(|w| w.id == a).unwrap().lifecycle,
            WindowLifecycle::Minimized
        );
        close_focused(&mut wm);
    }

    #[test]
    fn lifecycle_labels_cover_all() {
        for l in [
            WindowLifecycle::Created,
            WindowLifecycle::Visible,
            WindowLifecycle::Focused,
            WindowLifecycle::Minimized,
            WindowLifecycle::Closed,
        ] {
            assert!(!lifecycle_label(l).is_empty());
        }
    }
}
