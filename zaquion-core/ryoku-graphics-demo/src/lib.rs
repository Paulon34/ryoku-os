//! Ryoku graphics demo — First Pixels prototype (Mission 014 / 014.1 / 014.2).
//!
//! Builds an in-memory RGB24 framebuffer with a static title, then blits into a
//! caller-provided `/dev/fb0` mapping when a real framebuffer node exists.
//! Prefers fbdev. DRM-only (card without fb0) is reported honestly — no dumb-buffer
//! modeset/3D in this mission (isolated for a later step).
//!
//! Mission 014.2: geometry validation + **explicit** mmap length (never file-size
//! mmap of `/dev/fb0`, which is typically a 0-length char device).
//!
//! **`FIRST_PIXELS` is never auto-claimed PASS** — requires human visual confirmation.
//! Creating a software buffer alone is **not** a present.

#![forbid(unsafe_code)]

use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub const DEMO_IDENTITY: &str = "ryoku-graphics-demo";

/// Lines drawn into the software buffer (and onto fb0 when present).
pub const TITLE_LINES: &[&str] = &["RYOKU OS", "Minimal Developer Preview", "Rust Userland"];

/// Absolute upper bound on a single fb map (guard against absurd ioctl/sysfs values).
pub const MAX_FB_MAP_BYTES: usize = 64 * 1024 * 1024;

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FbGeometry {
    pub width: u32,
    pub height: u32,
    pub bpp: u32,
    pub stride: u32,
}

/// Validated map plan derived from geometry (+ optional `smem_len` from fixinfo).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FbMapPlan {
    pub geom: FbGeometry,
    /// Bytes required for visible scanout (`stride * height`).
    pub visible_bytes: usize,
    /// Length to request from `mmap` (≥ `visible_bytes`; may be `smem_len`).
    pub map_len: usize,
    pub source: &'static str,
}

/// Bytes per pixel for supported formats.
pub fn bytes_per_pixel(bpp: u32) -> Result<u32, String> {
    match bpp {
        24 | 32 => Ok(bpp / 8),
        _ => Err(format!(
            "{DEMO_IDENTITY}: unsupported bits_per_pixel={bpp} (need 24 or 32)"
        )),
    }
}

/// Compute `stride * height` with overflow checks.
pub fn checked_visible_bytes(stride: u32, height: u32) -> Result<usize, String> {
    let stride_us = stride as usize;
    let height_us = height as usize;
    stride_us.checked_mul(height_us).ok_or_else(|| {
        format!("{DEMO_IDENTITY}: stride*height overflow (stride={stride} height={height})")
    })
}

/// Validate width/height/bpp/stride and produce an mmap plan.
///
/// `smem_len_hint`: from `FBIOGET_FSCREENINFO.smem_len` when available.
pub fn validate_fb_geometry(
    geom: FbGeometry,
    smem_len_hint: Option<u32>,
    source: &'static str,
) -> Result<FbMapPlan, String> {
    if geom.width == 0 || geom.height == 0 {
        return Err(format!(
            "{DEMO_IDENTITY}: invalid geometry — zero width/height ({}x{})",
            geom.width, geom.height
        ));
    }
    let bpp_bytes = bytes_per_pixel(geom.bpp)?;
    let min_stride = geom
        .width
        .checked_mul(bpp_bytes)
        .ok_or_else(|| format!("{DEMO_IDENTITY}: width*bpp overflow"))?;
    if geom.stride < min_stride {
        return Err(format!(
            "{DEMO_IDENTITY}: stride {} < min {} (width={} bpp={})",
            geom.stride, min_stride, geom.width, geom.bpp
        ));
    }
    let visible = checked_visible_bytes(geom.stride, geom.height)?;
    if visible == 0 {
        return Err(format!("{DEMO_IDENTITY}: visible capacity is zero"));
    }
    if visible > MAX_FB_MAP_BYTES {
        return Err(format!(
            "{DEMO_IDENTITY}: visible capacity {visible} exceeds MAX_FB_MAP_BYTES={MAX_FB_MAP_BYTES}"
        ));
    }

    let map_len = match smem_len_hint {
        Some(smem) => {
            let smem_us = smem as usize;
            if smem_us < visible {
                return Err(format!(
                    "{DEMO_IDENTITY}: smem_len={smem} < visible capacity={visible} \
                     (geom {}x{} bpp={} stride={})",
                    geom.width, geom.height, geom.bpp, geom.stride
                ));
            }
            if smem_us > MAX_FB_MAP_BYTES {
                return Err(format!(
                    "{DEMO_IDENTITY}: smem_len={smem} exceeds MAX_FB_MAP_BYTES={MAX_FB_MAP_BYTES}"
                ));
            }
            smem_us
        }
        None => visible,
    };

    Ok(FbMapPlan {
        geom,
        visible_bytes: visible,
        map_len,
        source,
    })
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
///
/// Writes at most `min(src, geom)` pixels; never past `visible` capacity. Source may be
/// smaller than the FB (title buffer vs odd QEMU modes like 941×474).
pub fn blit_rgb_to_fb(map: &mut [u8], geom: &FbGeometry, src: &RgbBuffer) -> io::Result<()> {
    let plan = validate_fb_geometry(geom.clone(), None, "blit")
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    if map.len() < plan.visible_bytes {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            format!(
                "mmap shorter than stride*height: map_len={} visible={} \
                 (geom {}x{} bpp={} stride={})",
                map.len(),
                plan.visible_bytes,
                geom.width,
                geom.height,
                geom.bpp,
                geom.stride
            ),
        ));
    }
    let bpp = geom.bpp;
    let bpp_bytes = (bpp / 8) as usize;
    // Clear only the visible region (not beyond reported capacity).
    for b in map.iter_mut().take(plan.visible_bytes) {
        *b = 0;
    }
    let copy_w = geom.width.min(src.width);
    let copy_h = geom.height.min(src.height);
    for y in 0..copy_h {
        for x in 0..copy_w {
            let si = ((y as usize) * (src.width as usize) + (x as usize)) * 3;
            if si + 2 >= src.pixels.len() {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "source buffer truncated",
                ));
            }
            let r = src.pixels[si];
            let g = src.pixels[si + 1];
            let b = src.pixels[si + 2];
            let di = (y as usize) * (geom.stride as usize) + (x as usize) * bpp_bytes;
            if di + bpp_bytes > plan.visible_bytes {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("OOB dest pixel x={x} y={y} di={di} bpp_bytes={bpp_bytes}"),
                ));
            }
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
                 (dumb-buffer/modeset not enabled; prefer fbdev path). \
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
    // Validate early so callers see clear errors before mmap.
    let _ = validate_fb_geometry(geom.clone(), None, "sysfs")?;
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
        // Software-only must not claim present.
        let soft = format_outcome(&PresentOutcome::SoftwareOnly {
            width: 640,
            height: 480,
        });
        assert!(soft.contains("NOT_RUN"));
        assert!(soft.contains("no present"));
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

    #[test]
    fn valid_paulo_dims_941x474() {
        // Paulo NixOS FAIL_MANUAL case: 941×474 32bpp stride 3764.
        let geom = FbGeometry {
            width: 941,
            height: 474,
            bpp: 32,
            stride: 3764,
        };
        let plan = validate_fb_geometry(geom.clone(), None, "test").unwrap();
        assert_eq!(plan.visible_bytes, 3764 * 474);
        assert_eq!(plan.map_len, plan.visible_bytes);
        let with_smem =
            validate_fb_geometry(geom, Some(plan.visible_bytes as u32), "ioctl").unwrap();
        assert_eq!(with_smem.map_len, with_smem.visible_bytes);
    }

    #[test]
    fn padded_stride_is_accepted() {
        let geom = FbGeometry {
            width: 100,
            height: 50,
            bpp: 32,
            stride: 512, // > 100*4
        };
        let plan = validate_fb_geometry(geom.clone(), None, "test").unwrap();
        assert_eq!(plan.visible_bytes, 512 * 50);
        let mut map = vec![0u8; plan.map_len];
        let src = RgbBuffer::new(64, 32, (1, 2, 3));
        blit_rgb_to_fb(&mut map, &geom, &src).unwrap();
    }

    #[test]
    fn short_map_fails_with_sizes() {
        let geom = FbGeometry {
            width: 10,
            height: 10,
            bpp: 32,
            stride: 40,
        };
        let mut map = vec![0u8; 40]; // only one row
        let src = RgbBuffer::new(10, 10, (0, 0, 0));
        let err = blit_rgb_to_fb(&mut map, &geom, &src).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("mmap shorter"));
        assert!(msg.contains("map_len=40"));
        assert!(msg.contains("visible=400"));
    }

    #[test]
    fn absurd_capacity_rejected() {
        // Two u32s always fit in usize on 64-bit; MAX_FB_MAP_BYTES is the guard.
        let err = validate_fb_geometry(
            FbGeometry {
                width: 1,
                height: u32::MAX,
                bpp: 32,
                stride: u32::MAX,
            },
            None,
            "test",
        )
        .unwrap_err();
        assert!(err.contains("MAX_FB_MAP_BYTES"), "{err}");
        // checked_visible_bytes still uses checked_mul (defensive on 32-bit).
        assert!(checked_visible_bytes(64, 48).unwrap() == 64 * 48);
    }

    #[test]
    fn invalid_zero_geometry_rejected() {
        let err = validate_fb_geometry(
            FbGeometry {
                width: 0,
                height: 480,
                bpp: 32,
                stride: 1920,
            },
            None,
            "test",
        )
        .unwrap_err();
        assert!(err.contains("zero"));
    }

    #[test]
    fn unsupported_bpp_rejected() {
        let err = validate_fb_geometry(
            FbGeometry {
                width: 100,
                height: 100,
                bpp: 16,
                stride: 200,
            },
            None,
            "test",
        )
        .unwrap_err();
        assert!(err.contains("unsupported bits_per_pixel=16"));
    }

    #[test]
    fn image_smaller_than_fb_blits_without_oob() {
        let geom = FbGeometry {
            width: 941,
            height: 474,
            bpp: 32,
            stride: 3764,
        };
        let plan = validate_fb_geometry(geom.clone(), None, "test").unwrap();
        let mut map = vec![0u8; plan.map_len];
        let mut src = RgbBuffer::new(320, 200, (0, 0, 0));
        render_title(&mut src);
        blit_rgb_to_fb(&mut map, &geom, &src).unwrap();
        // A title pixel should land somewhere in the first 320×200 region.
        assert!(map.iter().any(|&b| b != 0));
    }

    #[test]
    fn map_size_calc_prefers_smem_when_larger() {
        let geom = FbGeometry {
            width: 8,
            height: 8,
            bpp: 32,
            stride: 32,
        };
        let plan = validate_fb_geometry(geom, Some(4096), "ioctl").unwrap();
        assert_eq!(plan.visible_bytes, 32 * 8);
        assert_eq!(plan.map_len, 4096);
    }

    #[test]
    fn smem_shorter_than_visible_rejected() {
        let geom = FbGeometry {
            width: 8,
            height: 8,
            bpp: 32,
            stride: 32,
        };
        let err = validate_fb_geometry(geom, Some(16), "ioctl").unwrap_err();
        assert!(err.contains("smem_len"));
    }

    #[test]
    fn stride_too_small_rejected() {
        let err = validate_fb_geometry(
            FbGeometry {
                width: 100,
                height: 10,
                bpp: 32,
                stride: 100, // need >= 400
            },
            None,
            "test",
        )
        .unwrap_err();
        assert!(err.contains("stride"));
    }
}
