//! Guest `/dev/input/event*` (evdev) — Mission 015.1.
//!
//! Opens only paths under the guest graphics root (default `/`). Never touches
//! the host `/dev/input`. No Bash / Hyprland / Wayland.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::mem;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use libc::input_event;

use ryoku_shell_preview::SHELL_IDENTITY;

/// Linux input event types / codes we care about (subset).
pub const EV_SYN: u16 = 0x00;
pub const EV_KEY: u16 = 0x01;
pub const EV_REL: u16 = 0x02;
pub const EV_ABS: u16 = 0x03;

pub const REL_X: u16 = 0x00;
pub const REL_Y: u16 = 0x01;

pub const ABS_X: u16 = 0x00;
pub const ABS_Y: u16 = 0x01;

pub const BTN_LEFT: u16 = 0x110;
pub const BTN_RIGHT: u16 = 0x111;
pub const BTN_TOUCH: u16 = 0x14a;

pub const KEY_ESC: u16 = 1;
pub const KEY_ENTER: u16 = 28;
pub const KEY_LEFT: u16 = 105;
pub const KEY_RIGHT: u16 = 106;
pub const KEY_UP: u16 = 103;
pub const KEY_DOWN: u16 = 108;
pub const KEY_TAB: u16 = 15;
pub const KEY_SPACE: u16 = 57;

/// QEMU virtio-tablet default ABS range (used when mapping to FB).
pub const DEFAULT_ABS_MAX: i32 = 32767;

/// Decoded high-level action for the shell event loop.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputAction {
    /// Absolute pointer sample (tablet). `x`/`y` already in FB pixels.
    AbsSample {
        x: Option<i32>,
        y: Option<i32>,
    },
    /// Relative pointer delta (mouse).
    RelDelta {
        dx: i32,
        dy: i32,
    },
    Button {
        code: u16,
        pressed: bool,
    },
    Key {
        code: u16,
        pressed: bool,
    },
}

/// One opened guest evdev node (non-blocking).
#[derive(Debug)]
pub struct EvdevDevice {
    pub path: PathBuf,
    file: File,
}

impl EvdevDevice {
    fn open(path: PathBuf) -> io::Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(&path)?;
        Ok(Self { path, file })
    }

    /// Drain pending events (non-blocking).
    pub fn poll_actions(&mut self, fb_w: i32, fb_h: i32) -> Vec<InputAction> {
        let mut out = Vec::new();
        let mut buf = [0u8; mem::size_of::<input_event>() * 32];
        loop {
            match self.file.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let sz = mem::size_of::<input_event>();
                    let mut off = 0;
                    while off + sz <= n {
                        let ev = unsafe {
                            let ptr = buf.as_ptr().add(off) as *const input_event;
                            ptr.read_unaligned()
                        };
                        off += sz;
                        if let Some(a) = decode_event(&ev, fb_w, fb_h) {
                            out.push(a);
                        }
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                Err(e) if e.raw_os_error() == Some(libc::EAGAIN) => break,
                Err(_) => break,
            }
        }
        out
    }
}

fn map_abs(value: i32, fb_extent: i32) -> i32 {
    let max = DEFAULT_ABS_MAX.max(1);
    let mapped =
        (i64::from(value) * i64::from(fb_extent.saturating_sub(1)) / i64::from(max)) as i32;
    mapped.clamp(0, fb_extent.saturating_sub(1))
}

fn decode_event(ev: &input_event, fb_w: i32, fb_h: i32) -> Option<InputAction> {
    match ev.type_ {
        EV_SYN => None,
        EV_REL => match ev.code {
            REL_X => Some(InputAction::RelDelta {
                dx: ev.value,
                dy: 0,
            }),
            REL_Y => Some(InputAction::RelDelta {
                dx: 0,
                dy: ev.value,
            }),
            _ => None,
        },
        EV_ABS => match ev.code {
            ABS_X => Some(InputAction::AbsSample {
                x: Some(map_abs(ev.value, fb_w)),
                y: None,
            }),
            ABS_Y => Some(InputAction::AbsSample {
                x: None,
                y: Some(map_abs(ev.value, fb_h)),
            }),
            _ => None,
        },
        EV_KEY => {
            let pressed = ev.value != 0;
            if matches!(ev.code, BTN_LEFT | BTN_RIGHT | BTN_TOUCH) {
                Some(InputAction::Button {
                    code: ev.code,
                    pressed,
                })
            } else {
                Some(InputAction::Key {
                    code: ev.code,
                    pressed,
                })
            }
        }
        _ => None,
    }
}

/// Scan guest `…/dev/input/event*` under `root` (guest `/` in VM).
pub fn scan_evdev_devices(root: &Path) -> Result<Vec<EvdevDevice>, String> {
    let dir = root.join("dev/input");
    if !dir.is_dir() {
        return Err(format!(
            "{SHELL_IDENTITY}: WARN no {} (guest input nodes missing)",
            dir.display()
        ));
    }
    let mut paths: Vec<PathBuf> = fs::read_dir(&dir)
        .map_err(|e| format!("{SHELL_IDENTITY}: WARN read {}: {e}", dir.display()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with("event"))
        })
        .collect();
    paths.sort();
    let mut devices = Vec::new();
    for p in paths {
        match EvdevDevice::open(p.clone()) {
            Ok(d) => {
                eprintln!("{SHELL_IDENTITY}: opened guest evdev {}", d.path.display());
                devices.push(d);
            }
            Err(err) => {
                eprintln!("{SHELL_IDENTITY}: WARN open {} failed: {err}", p.display());
            }
        }
    }
    if devices.is_empty() {
        return Err(format!(
            "{SHELL_IDENTITY}: WARN no usable guest /dev/input/event* under {}",
            root.display()
        ));
    }
    Ok(devices)
}

/// Rate-limited redraw helper (avoids busy FB thrash).
pub struct RedrawGate {
    min_interval: Duration,
    last: Option<Instant>,
}

impl RedrawGate {
    #[must_use]
    pub fn new(min_interval: Duration) -> Self {
        Self {
            min_interval,
            last: None,
        }
    }

    /// Returns true when a redraw is allowed now (and records the time).
    pub fn allow(&mut self) -> bool {
        let now = Instant::now();
        if let Some(last) = self.last {
            if now.duration_since(last) < self.min_interval {
                return false;
            }
        }
        self.last = Some(now);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redraw_gate_rate_limits() {
        let mut g = RedrawGate::new(Duration::from_millis(50));
        assert!(g.allow());
        assert!(!g.allow());
    }

    #[test]
    fn scan_missing_dir_warns() {
        let err = scan_evdev_devices(Path::new("/tmp/ryoku-no-such-root-0151")).unwrap_err();
        assert!(err.contains("WARN"));
    }

    #[test]
    fn map_abs_clamps() {
        assert_eq!(map_abs(0, 100), 0);
        assert_eq!(map_abs(DEFAULT_ABS_MAX, 100), 99);
    }
}
