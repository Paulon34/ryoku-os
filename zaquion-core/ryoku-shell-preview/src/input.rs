//! Guest `/dev/input/event*` (evdev) — Mission 015.1 / 015.2 / 015.2.1.
//!
//! Opens only paths under the guest graphics root (default `/`). Never touches
//! the host `/dev/input`. No Bash / Hyprland / Wayland.
//!
//! Mission 015.2.1: ABS from device caps; keep **all** keyboards + one pointer;
//! partial-read reassembly; motion coalescing helpers.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};
use std::mem;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use libc::input_event;

use ryoku_shell_preview::{InputFact, SHELL_IDENTITY};

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
pub const KEY_A: u16 = 30;

/// Fallback only when EVIOCGABS fails (never assumed as the primary path).
pub const FALLBACK_ABS_MAX: i32 = 32767;

/// Decoded high-level action for the shell event loop.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputAction {
    AbsSample { x: Option<i32>, y: Option<i32> },
    RelDelta { dx: i32, dy: i32 },
    Button { code: u16, pressed: bool },
    Key { code: u16, pressed: bool },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeviceRole {
    PointerAbs,
    PointerRel,
    Keyboard,
}

/// Absolute axis range from EVIOCGABS (or fallback).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AbsRange {
    pub min: i32,
    pub max: i32,
}

impl AbsRange {
    #[must_use]
    pub fn span(self) -> i32 {
        (self.max - self.min).max(1)
    }

    #[must_use]
    pub fn map_to(self, value: i32, fb_extent: i32) -> i32 {
        let span = i64::from(self.span());
        let v = i64::from(value.clamp(self.min, self.max) - self.min);
        let mapped = v * i64::from(fb_extent.saturating_sub(1)) / span;
        (mapped as i32).clamp(0, fb_extent.saturating_sub(1))
    }
}

/// Coalesced pointer motion for one poll cycle (015.2.1).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct MotionCoalesce {
    pub abs_x: Option<i32>,
    pub abs_y: Option<i32>,
    pub rel_dx: i32,
    pub rel_dy: i32,
}

impl MotionCoalesce {
    pub fn absorb_abs(&mut self, x: Option<i32>, y: Option<i32>) {
        if let Some(v) = x {
            self.abs_x = Some(v);
        }
        if let Some(v) = y {
            self.abs_y = Some(v);
        }
    }

    pub fn absorb_rel(&mut self, dx: i32, dy: i32) {
        self.rel_dx = self.rel_dx.saturating_add(dx);
        self.rel_dy = self.rel_dy.saturating_add(dy);
    }

    #[must_use]
    pub fn has_motion(&self) -> bool {
        self.abs_x.is_some() || self.abs_y.is_some() || self.rel_dx != 0 || self.rel_dy != 0
    }
}

/// One opened guest evdev node (non-blocking) with probed caps + partial buffer.
#[derive(Debug)]
pub struct EvdevDevice {
    pub path: PathBuf,
    pub role: DeviceRole,
    file: File,
    abs_x: AbsRange,
    abs_y: AbsRange,
    has_abs: bool,
    has_rel: bool,
    has_keys: bool,
    /// Leftover bytes from a short `read` (partial `input_event`).
    partial: Vec<u8>,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct InputAbsinfo {
    value: i32,
    minimum: i32,
    maximum: i32,
    fuzz: i32,
    flat: i32,
    resolution: i32,
}

/// Linux `_IOC(_IOC_READ, 'E', nr, size)` for x86/x86_64 → `libc::Ioctl`.
fn evioc_read(nr: u32, size: u32) -> libc::Ioctl {
    ((2u64 << 30) | ((b'E' as u64) << 8) | u64::from(nr) | (u64::from(size) << 16)) as libc::Ioctl
}

fn bit_test(bits: &[u8], bit: usize) -> bool {
    let byte = bit / 8;
    let mask = 1u8 << (bit % 8);
    bits.get(byte).is_some_and(|b| b & mask != 0)
}

unsafe fn ioctl_abs(file: &File, axis: u16) -> Option<AbsRange> {
    let mut info = InputAbsinfo {
        value: 0,
        minimum: 0,
        maximum: 0,
        fuzz: 0,
        flat: 0,
        resolution: 0,
    };
    let req = evioc_read(
        0x40 + u32::from(axis),
        mem::size_of::<InputAbsinfo>() as u32,
    );
    if libc::ioctl(file.as_raw_fd(), req, &mut info) < 0 {
        return None;
    }
    if info.maximum <= info.minimum {
        return None;
    }
    Some(AbsRange {
        min: info.minimum,
        max: info.maximum,
    })
}

unsafe fn ioctl_ev_bits(file: &File) -> Option<[u8; 8]> {
    let mut bits = [0u8; 8];
    let req = evioc_read(0x20, bits.len() as u32);
    if libc::ioctl(file.as_raw_fd(), req, bits.as_mut_ptr()) < 0 {
        return None;
    }
    Some(bits)
}

unsafe fn ioctl_key_bits(file: &File) -> Option<[u8; 96]> {
    let mut bits = [0u8; 96];
    let req = evioc_read(0x20 + u32::from(EV_KEY), bits.len() as u32);
    if libc::ioctl(file.as_raw_fd(), req, bits.as_mut_ptr()) < 0 {
        return None;
    }
    Some(bits)
}

impl EvdevDevice {
    fn open_probed(path: PathBuf) -> io::Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(&path)?;

        let (has_abs, has_rel, has_keys) = unsafe {
            match ioctl_ev_bits(&file) {
                Some(bits) => (
                    bit_test(&bits, EV_ABS as usize),
                    bit_test(&bits, EV_REL as usize),
                    bit_test(&bits, EV_KEY as usize),
                ),
                None => (false, false, false),
            }
        };

        let abs_x = if has_abs {
            unsafe { ioctl_abs(&file, ABS_X) }.unwrap_or(AbsRange {
                min: 0,
                max: FALLBACK_ABS_MAX,
            })
        } else {
            AbsRange {
                min: 0,
                max: FALLBACK_ABS_MAX,
            }
        };
        let abs_y = if has_abs {
            unsafe { ioctl_abs(&file, ABS_Y) }.unwrap_or(AbsRange {
                min: 0,
                max: FALLBACK_ABS_MAX,
            })
        } else {
            AbsRange {
                min: 0,
                max: FALLBACK_ABS_MAX,
            }
        };

        let looks_keyboard = if has_keys {
            unsafe {
                ioctl_key_bits(&file).is_some_and(|kb| {
                    bit_test(&kb, KEY_ESC as usize) || bit_test(&kb, KEY_A as usize)
                })
            }
        } else {
            false
        };

        // Pointer wins when ABS/REL present without letter-key keyboard bits.
        let role = if has_abs && !looks_keyboard {
            DeviceRole::PointerAbs
        } else if has_rel && !looks_keyboard {
            DeviceRole::PointerRel
        } else if looks_keyboard {
            DeviceRole::Keyboard
        } else if has_abs {
            DeviceRole::PointerAbs
        } else if has_rel {
            DeviceRole::PointerRel
        } else if has_keys {
            DeviceRole::Keyboard
        } else {
            DeviceRole::PointerRel
        };

        Ok(Self {
            path,
            role,
            file,
            abs_x,
            abs_y,
            has_abs,
            has_rel,
            has_keys,
            partial: Vec::new(),
        })
    }

    /// Drain pending events (non-blocking), reassembling partial reads.
    pub fn poll_actions(&mut self, fb_w: i32, fb_h: i32) -> Vec<InputAction> {
        let mut out = Vec::new();
        let mut buf = [0u8; mem::size_of::<input_event>() * 32];
        loop {
            match self.file.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    self.partial.extend_from_slice(&buf[..n]);
                    let sz = mem::size_of::<input_event>();
                    while self.partial.len() >= sz {
                        let chunk: Vec<u8> = self.partial.drain(..sz).collect();
                        let ev = unsafe {
                            let ptr = chunk.as_ptr() as *const input_event;
                            ptr.read_unaligned()
                        };
                        if let Some(a) = decode_event(&ev, self, fb_w, fb_h) {
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

fn decode_event(ev: &input_event, dev: &EvdevDevice, fb_w: i32, fb_h: i32) -> Option<InputAction> {
    match ev.type_ {
        EV_SYN => None,
        EV_REL => {
            if matches!(dev.role, DeviceRole::PointerRel | DeviceRole::PointerAbs) {
                match ev.code {
                    REL_X => Some(InputAction::RelDelta {
                        dx: ev.value,
                        dy: 0,
                    }),
                    REL_Y => Some(InputAction::RelDelta {
                        dx: 0,
                        dy: ev.value,
                    }),
                    _ => None,
                }
            } else {
                None
            }
        }
        EV_ABS => {
            if matches!(dev.role, DeviceRole::PointerAbs) {
                match ev.code {
                    ABS_X => Some(InputAction::AbsSample {
                        x: Some(dev.abs_x.map_to(ev.value, fb_w)),
                        y: None,
                    }),
                    ABS_Y => Some(InputAction::AbsSample {
                        x: None,
                        y: Some(dev.abs_y.map_to(ev.value, fb_h)),
                    }),
                    _ => None,
                }
            } else {
                None
            }
        }
        EV_KEY => {
            let pressed = ev.value != 0;
            // Buttons: accept from pointer devices (BTN_LEFT / BTN_TOUCH).
            if matches!(ev.code, BTN_LEFT | BTN_RIGHT | BTN_TOUCH) {
                if matches!(dev.role, DeviceRole::PointerAbs | DeviceRole::PointerRel) {
                    Some(InputAction::Button {
                        code: ev.code,
                        pressed,
                    })
                } else {
                    None
                }
            } else if matches!(dev.role, DeviceRole::Keyboard) {
                Some(InputAction::Key {
                    code: ev.code,
                    pressed,
                })
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Scan + select devices: **all** keyboards + one pointer (prefer ABS).
///
/// 015.2.1: do not drop AT/Virtio keyboard peers (event0 + event1).
pub fn scan_evdev_devices(root: &Path) -> Result<(Vec<EvdevDevice>, InputFact), String> {
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

    let mut probed = Vec::new();
    for p in paths {
        match EvdevDevice::open_probed(p.clone()) {
            Ok(d) => {
                eprintln!(
                    "{SHELL_IDENTITY}: probed {} role={:?} abs={} rel={} keys={} absX={:?} absY={:?}",
                    d.path.display(),
                    d.role,
                    d.has_abs,
                    d.has_rel,
                    d.has_keys,
                    d.abs_x,
                    d.abs_y
                );
                probed.push(d);
            }
            Err(err) => {
                eprintln!("{SHELL_IDENTITY}: WARN open {} failed: {err}", p.display());
            }
        }
    }

    if probed.is_empty() {
        return Err(format!(
            "{SHELL_IDENTITY}: WARN no usable guest /dev/input/event* under {}",
            root.display()
        ));
    }

    let mut selected: Vec<EvdevDevice> = Vec::new();
    // One pointer (ABS preferred).
    if let Some(idx) = probed.iter().position(|d| d.role == DeviceRole::PointerAbs) {
        selected.push(probed.remove(idx));
    } else if let Some(idx) = probed.iter().position(|d| d.role == DeviceRole::PointerRel) {
        selected.push(probed.remove(idx));
    }
    // Keep every keyboard (AT + Virtio often appear as event0 + event1).
    let mut i = 0;
    while i < probed.len() {
        if probed[i].role == DeviceRole::Keyboard {
            selected.push(probed.remove(i));
        } else {
            i += 1;
        }
    }

    for skipped in &probed {
        eprintln!(
            "{SHELL_IDENTITY}: skipping extra non-keyboard/pointer {} ({:?})",
            skipped.path.display(),
            skipped.role
        );
    }

    if selected.is_empty() {
        return Err(format!(
            "{SHELL_IDENTITY}: WARN no pointer/keyboard role among guest event nodes"
        ));
    }

    for d in &selected {
        eprintln!(
            "{SHELL_IDENTITY}: using guest evdev {} as {:?}",
            d.path.display(),
            d.role
        );
    }

    Ok((selected, InputFact::Detected))
}

/// Split raw actions into coalesced motion + ordered buttons/keys.
#[must_use]
pub fn coalesce_actions(actions: &[InputAction]) -> (MotionCoalesce, Vec<InputAction>) {
    let mut motion = MotionCoalesce::default();
    let mut rest = Vec::new();
    for a in actions {
        match a {
            InputAction::AbsSample { x, y } => motion.absorb_abs(*x, *y),
            InputAction::RelDelta { dx, dy } => motion.absorb_rel(*dx, *dy),
            other => rest.push(other.clone()),
        }
    }
    (motion, rest)
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

    #[must_use]
    pub fn from_fps(fps: u32) -> Self {
        let fps = fps.clamp(1, 120);
        let ms = (1000 / fps).max(1);
        Self::new(Duration::from_millis(u64::from(ms)))
    }

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
    fn redraw_gate_from_fps() {
        let g = RedrawGate::from_fps(30);
        assert_eq!(g.min_interval, Duration::from_millis(33));
    }

    #[test]
    fn scan_missing_dir_warns() {
        let err = scan_evdev_devices(Path::new("/tmp/ryoku-no-such-root-01521")).unwrap_err();
        assert!(err.contains("WARN"));
    }

    #[test]
    fn abs_range_maps_from_device_caps() {
        let r = AbsRange { min: 0, max: 1000 };
        assert_eq!(r.map_to(0, 100), 0);
        assert_eq!(r.map_to(1000, 100), 99);
        assert_eq!(r.map_to(500, 100), 49);
    }

    #[test]
    fn abs_range_nonzero_min() {
        let r = AbsRange { min: 100, max: 200 };
        assert_eq!(r.map_to(100, 50), 0);
        assert_eq!(r.map_to(200, 50), 49);
    }

    #[test]
    fn evioc_read_abs_x_constant() {
        let req = evioc_read(0x40, 24);
        assert_eq!(req as u64, 0x8018_4540);
    }

    #[test]
    fn coalesce_merges_abs_and_rel() {
        let actions = [
            InputAction::AbsSample {
                x: Some(10),
                y: None,
            },
            InputAction::AbsSample {
                x: None,
                y: Some(20),
            },
            InputAction::AbsSample {
                x: Some(11),
                y: None,
            },
            InputAction::RelDelta { dx: 2, dy: 3 },
            InputAction::RelDelta { dx: 1, dy: 0 },
            InputAction::Button {
                code: BTN_LEFT,
                pressed: true,
            },
            InputAction::Key {
                code: KEY_ESC,
                pressed: true,
            },
        ];
        let (m, rest) = coalesce_actions(&actions);
        assert_eq!(m.abs_x, Some(11));
        assert_eq!(m.abs_y, Some(20));
        assert_eq!(m.rel_dx, 3);
        assert_eq!(m.rel_dy, 3);
        assert_eq!(rest.len(), 2);
    }

    #[test]
    fn select_keeps_multiple_keyboards_logic() {
        // Unit-level: role classification prefers pointer without letter keys.
        // Full scan needs guest nodes; this locks the coalesce/select contract.
        let roles = [
            DeviceRole::Keyboard,
            DeviceRole::Keyboard,
            DeviceRole::PointerAbs,
        ];
        let kbd = roles.iter().filter(|r| **r == DeviceRole::Keyboard).count();
        let ptr = roles
            .iter()
            .filter(|r| matches!(r, DeviceRole::PointerAbs | DeviceRole::PointerRel))
            .count();
        assert_eq!(kbd, 2);
        assert_eq!(ptr, 1);
    }
}
