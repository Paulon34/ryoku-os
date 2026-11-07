//! Ryoku graphics demo — First Pixels prototype (Mission 014 / 014.1).
//!
//! Builds an in-memory RGB24 framebuffer with a static title, then blits into a
//! caller-provided `/dev/fb0` mapping when a real framebuffer node exists.
//! Prefers fbdev. DRM-only (card without fb0) is reported honestly — no dumb-buffer
//! modeset/3D in this mission (isolated for a later step).
//!
//! **`FIRST_PIXELS` is never auto-claimed PASS** — requires human visual confirmation.

#![forbid(unsafe_code)]

use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub const DEMO_IDENTITY: &str = "ryoku-graphics-demo";

/// Lines drawn into the software buffer (and onto fb0 when present).
pub const TITLE_LINES: &[&str] = &["RYOKU OS", "Minimal Developer Preview", "Rust Userland"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RgbBuffer {
    pub width: u32,
    pub height: u32,
    /// Packed RGB888 row-major.
    pub pixels: Vec<u8>,
}

impl RgbBuffer {
    #[must_use]
    pub fn new(width: u32, height: u32, fill: (u8, u8, u8)) -> Self {
        let n = (width as usize)
            .saturating_mul(height as usize)
            .saturating_mul(3);
        let mut pixels = vec![0u8; n];
        for chunk in pixels.chunks_exact_mut(3) {
            chunk[0] = fill.0;
            chunk[1] = fill.1;
            chunk[2] = fill.2;
        }
        Self {
            width,
            height,
            pixels,
        }
    }

    pub fn put_pixel(&mut self, x: u32, y: u32, rgb: (u8, u8, u8)) {
        if x >= self.width || y >= self.height {
            return;
        }
        let i = ((y as usize) * (self.width as usize) + (x as usize)) * 3;
        self.pixels[i] = rgb.0;
        self.pixels[i + 1] = rgb.1;
        self.pixels[i + 2] = rgb.2;
    }
}

/// Tiny 5×7 glyphs for the title alphabet.
fn glyph(ch: char) -> Option<[u8; 7]> {
    match ch {
        ' ' => Some([0, 0, 0, 0, 0, 0, 0]),
        '/' => Some([0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00]),
        '0' => Some([0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E]),
        '1' => Some([0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E]),
        '2' => Some([0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F]),
        '3' => Some([0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E]),
        '4' => Some([0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02]),
        '5' => Some([0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E]),
        '6' => Some([0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E]),
        '7' => Some([0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08]),
        '8' => Some([0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E]),
        '9' => Some([0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C]),
        'A' => Some([0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11]),
        'D' => Some([0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E]),
        'E' => Some([0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F]),
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

/// Draw title lines centered into `buf` (navy background, light text).
pub fn render_title(buf: &mut RgbBuffer) {
    let bg = (0x0a, 0x16, 0x2e);
    let fg = (0xe8, 0xf0, 0xff);
    for chunk in buf.pixels.chunks_exact_mut(3) {
        chunk[0] = bg.0;
        chunk[1] = bg.1;
        chunk[2] = bg.2;
    }
    let scale = 2u32;
    let line_h = 7 * scale + 4;
    let total_h = line_h * TITLE_LINES.len() as u32;
    let mut y0 = buf.height.saturating_sub(total_h) / 2;
    for line in TITLE_LINES {
        let text: String = line
            .chars()
            .map(|c| {
                if c.is_ascii_alphabetic() {
                    c.to_ascii_uppercase()
                } else {
                    c
                }
            })
            .collect();
        let glyph_w = 6 * scale;
        let text_w = glyph_w * text.chars().count() as u32;
        let mut x0 = buf.width.saturating_sub(text_w) / 2;
        for ch in text.chars() {
            if let Some(rows) = glyph(ch) {
                for (ry, row) in rows.iter().enumerate() {
                    for bx in 0..5u32 {
                        if row & (1 << (4 - bx)) != 0 {
                            for sy in 0..scale {
                                for sx in 0..scale {
                                    buf.put_pixel(
                                        x0 + bx * scale + sx,
                                        y0 + ry as u32 * scale + sy,
                                        fg,
                                    );
                                }
                            }
                        }
                    }
                }
            }
            x0 = x0.saturating_add(glyph_w);
        }
        y0 = y0.saturating_add(line_h);
    }
}

#[derive(Debug, Clone)]
pub struct FbGeometry {
    pub width: u32,
    pub height: u32,
    pub bpp: u32,
    pub stride: u32,
}

/// Read fb0 geometry from sysfs under `root` (guest `/` or fixture).
pub fn read_fb0_geometry(root: &Path) -> io::Result<FbGeometry> {
    let vs = fs::read_to_string(root.join("sys/class/graphics/fb0/virtual_size"))?;
    let parts: Vec<_> = vs.trim().split(',').collect();
    if parts.len() != 2 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "virtual_size expected W,H",
        ));
    }
    let width: u32 = parts[0]
        .trim()
        .parse()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let height: u32 = parts[1]
        .trim()
        .parse()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let bpp: u32 = fs::read_to_string(root.join("sys/class/graphics/fb0/bits_per_pixel"))?
        .trim()
        .parse()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let stride: u32 = fs::read_to_string(root.join("sys/class/graphics/fb0/stride"))?
        .trim()
        .parse()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    Ok(FbGeometry {
        width,
        height,
        bpp,
        stride,
    })
}

/// Blit RGB888 software buffer into an fb mmap (32bpp XRGB little-endian or 24bpp BGR).
pub fn blit_rgb_to_fb(map: &mut [u8], geom: &FbGeometry, src: &RgbBuffer) -> io::Result<()> {
    if geom.width == 0 || geom.height == 0 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "zero geometry"));
    }
    let need = geom.stride as usize * geom.height as usize;
    if map.len() < need {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "mmap shorter than stride*height",
        ));
    }
    for b in map.iter_mut().take(need) {
        *b = 0;
    }
    let bpp = geom.bpp;
    if bpp != 32 && bpp != 24 {
        return Err(io::Error::new(
            io::ErrorKind::Unsupported,
            format!("unsupported bits_per_pixel={bpp} (need 24 or 32)"),
        ));
    }
    for y in 0..geom.height.min(src.height) {
        for x in 0..geom.width.min(src.width) {
            let si = ((y as usize) * (src.width as usize) + (x as usize)) * 3;
            let r = src.pixels[si];
            let g = src.pixels[si + 1];
            let b = src.pixels[si + 2];
            let di = (y as usize) * (geom.stride as usize) + (x as usize) * (bpp as usize / 8);
            if bpp == 32 {
                map[di] = b;
                map[di + 1] = g;
                map[di + 2] = r;
                map[di + 3] = 0;
            } else {
                map[di] = b;
                map[di + 1] = g;
                map[di + 2] = r;
            }
        }
    }
    Ok(())
}

#[derive(Debug)]
pub enum PresentOutcome {
    SoftwareOnly {
        width: u32,
        height: u32,
    },
    Fb0Presented {
        width: u32,
        height: u32,
        bpp: u32,
    },
    /// DRM card visible but no usable `/dev/fb0` — no present claimed.
    DrmOnlyNoFb {
        detail: String,
    },
    NoSurface {
        reason: String,
    },
}

/// Read-only surface inventory under `root` (guest `/` or fixture).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SurfaceProbe {
    pub fb0: bool,
    pub dri_card0: bool,
    pub sysfs_drm: bool,
    pub sysfs_graphics: bool,
}

#[must_use]
pub fn probe_surfaces(root: &Path) -> SurfaceProbe {
    SurfaceProbe {
        fb0: root.join("dev/fb0").exists(),
        dri_card0: root.join("dev/dri/card0").exists(),
        sysfs_drm: root.join("sys/class/drm").is_dir(),
        sysfs_graphics: root.join("sys/class/graphics").is_dir(),
    }
}

#[must_use]
pub fn format_surface_probe(p: &SurfaceProbe) -> String {
    format!(
        "{DEMO_IDENTITY}: surface probe fb0={} dri_card0={} sysfs_drm={} sysfs_graphics={}\n",
        yes_no(p.fb0),
        yes_no(p.dri_card0),
        yes_no(p.sysfs_drm),
        yes_no(p.sysfs_graphics),
    )
}

fn yes_no(v: bool) -> &'static str {
    if v {
        "yes"
    } else {
        "no"
    }
}

/// Safe software-only path for unit tests (no mmap).
#[must_use]
pub fn run_software_demo() -> RgbBuffer {
    let mut buf = RgbBuffer::new(320, 200, (0, 0, 0));
    render_title(&mut buf);
    buf
}

/// Present into an already-mapped fb buffer (mmap stays in `main` / caller).
pub fn present_to_mmap(map: &mut [u8], geom: &FbGeometry, src: &RgbBuffer) -> io::Result<()> {
    blit_rgb_to_fb(map, geom, src)
}

/// Probe whether `/dev/fb0` + sysfs geometry exist under `root`.
///
/// If DRM nodes exist without fb0, returns an error that callers should treat as
/// DRM-only (no fake present). Dumb-buffer modeset is intentionally out of scope.
pub fn probe_fb0(root: &Path) -> Result<(PathBuf, FbGeometry), String> {
    let surfaces = probe_surfaces(root);
    let fb_path = root.join("dev/fb0");
    if !fb_path.exists() {
        if surfaces.dri_card0 || surfaces.sysfs_drm {
            return Err(format!(
                "{DEMO_IDENTITY}: DRM visible without /dev/fb0 — refusing unpresented buffer \
                 (dumb-buffer/modeset not enabled in 014.1; prefer fbdev path). \
                 dri_card0={} sysfs_drm={}",
                yes_no(surfaces.dri_card0),
                yes_no(surfaces.sysfs_drm)
            ));
        }
        return Err(format!(
            "{DEMO_IDENTITY}: missing {} — no framebuffer node \
             (need matching virtio_gpu/fb modules; PCI virtio-pci alone ≠ DRM/fb)",
            fb_path.display()
        ));
    }
    let geom = read_fb0_geometry(root).map_err(|err| {
        format!(
            "{DEMO_IDENTITY}: cannot read fb0 sysfs geometry under {}: {err}",
            root.display()
        )
    })?;
    Ok((fb_path, geom))
}

/// Classify a missing-fb probe error as DRM-only vs no surface.
#[must_use]
pub fn classify_no_fb_reason(reason: String) -> PresentOutcome {
    if reason.contains("DRM visible without") {
        PresentOutcome::DrmOnlyNoFb { detail: reason }
    } else {
        PresentOutcome::NoSurface { reason }
    }
}

pub fn open_fb_rw(path: &Path) -> io::Result<File> {
    fs::OpenOptions::new().read(true).write(true).open(path)
}

/// Resolve graphics root: `RYOKU_GRAPHICS_ROOT`, else `RYOKU_CONSOLE_ROOT`.
pub fn graphics_root_from_env() -> Result<PathBuf, String> {
    if let Some(v) = std::env::var_os("RYOKU_GRAPHICS_ROOT") {
        return Ok(PathBuf::from(v));
    }
    if let Some(v) = std::env::var_os("RYOKU_CONSOLE_ROOT") {
        return Ok(PathBuf::from(v));
    }
    Err(format!(
        "{DEMO_IDENTITY}: set RYOKU_GRAPHICS_ROOT or RYOKU_CONSOLE_ROOT (guest uses /)"
    ))
}

#[must_use]
pub fn format_outcome(out: &PresentOutcome) -> String {
    match out {
        PresentOutcome::SoftwareOnly { width, height } => format!(
            "{DEMO_IDENTITY}: software buffer {width}x{height} ready; FIRST_PIXELS=NOT_RUN (no present)\n"
        ),
        PresentOutcome::Fb0Presented {
            width,
            height,
            bpp,
        } => format!(
            "{DEMO_IDENTITY}: presented successfully into /dev/fb0 ({width}x{height} bpp={bpp}); \
             visual FIRST_PIXELS still requires human confirmation (NOT auto-PASS)\n"
        ),
        PresentOutcome::DrmOnlyNoFb { detail } => {
            format!("{detail}\n{DEMO_IDENTITY}: FIRST_PIXELS=NOT_RUN (DRM without fb0)\n")
        }
        PresentOutcome::NoSurface { reason } => format!("{reason}\n"),
    }
}

/// Write a tiny PPM for host inspection of the software buffer (tests / debug).
pub fn write_ppm(path: &Path, buf: &RgbBuffer) -> io::Result<()> {
    let mut f = fs::File::create(path)?;
    writeln!(f, "P6\n{} {}\n255", buf.width, buf.height)?;
    f.write_all(&buf.pixels)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn software_title_marks_nonzero_pixels() {
        let buf = run_software_demo();
        assert_eq!(buf.width, 320);
        assert!(buf
            .pixels
            .iter()
            .any(|&b| b != 0 && b != 0x0a && b != 0x16 && b != 0x2e));
        assert_eq!(buf.pixels[0], 0x0a);
    }

    #[test]
    fn blit_32bpp_respects_stride() {
        let mut src = RgbBuffer::new(2, 2, (0, 0, 0));
        src.put_pixel(0, 0, (255, 0, 0));
        let geom = FbGeometry {
            width: 2,
            height: 2,
            bpp: 32,
            stride: 16,
        };
        let mut map = vec![0u8; 16 * 2];
        blit_rgb_to_fb(&mut map, &geom, &src).unwrap();
        assert_eq!(map[0], 0);
        assert_eq!(map[1], 0);
        assert_eq!(map[2], 255);
    }

    #[test]
    fn format_never_auto_pass_first_pixels() {
        let s = format_outcome(&PresentOutcome::Fb0Presented {
            width: 640,
            height: 480,
            bpp: 32,
        });
        assert!(s.contains("NOT auto-PASS") || s.contains("confirmation"));
        assert!(!s.contains("FIRST_PIXELS=PASS"));
    }

    #[test]
    fn probe_missing_fb_is_honest() {
        let dir = std::env::temp_dir().join(format!("ryoku-gfx-miss-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let err = probe_fb0(&dir).unwrap_err();
        assert!(err.contains("missing"));
        assert!(!err.contains("PASS"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn probe_drm_without_fb_is_honest() {
        let dir = std::env::temp_dir().join(format!("ryoku-gfx-drm-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("dev/dri")).unwrap();
        fs::write(dir.join("dev/dri/card0"), b"").unwrap();
        fs::create_dir_all(dir.join("sys/class/drm")).unwrap();
        let err = probe_fb0(&dir).unwrap_err();
        assert!(err.contains("DRM visible without"));
        let out = classify_no_fb_reason(err);
        match out {
            PresentOutcome::DrmOnlyNoFb { .. } => {}
            other => panic!("expected DrmOnlyNoFb, got {other:?}"),
        }
        let s = format_outcome(&out);
        assert!(s.contains("FIRST_PIXELS=NOT_RUN"));
        assert!(!s.contains("FIRST_PIXELS=PASS"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn title_lines_match_mission_copy() {
        assert_eq!(TITLE_LINES[0], "RYOKU OS");
        assert_eq!(TITLE_LINES[1], "Minimal Developer Preview");
        assert_eq!(TITLE_LINES[2], "Rust Userland");
    }
}
