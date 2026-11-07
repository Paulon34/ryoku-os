//! Isolated unsafe: fbdev ioctl geometry + explicit-length mmap (Mission 014.2).
//!
//! `/dev/fb0` is a char device — `stat` size is typically 0. File-size mmap is
//! therefore wrong. We prefer `FBIOGET_VSCREENINFO` / `FBIOGET_FSCREENINFO`,
//! validate, then `MmapOptions::len(map_len).map_mut(...)`.

#![allow(unsafe_code)]

use std::fs::File;
use std::io;
use std::mem;
use std::os::fd::AsRawFd;

use memmap2::{MmapMut, MmapOptions};
use ryoku_graphics_demo::{validate_fb_geometry, FbGeometry, FbMapPlan, DEMO_IDENTITY};

/// `FBIOGET_VSCREENINFO` — linux/fb.h (`libc::Ioctl` is `c_ulong` on gnu, `c_int` on musl).
const FBIOGET_VSCREENINFO: libc::Ioctl = 0x4600 as libc::Ioctl;
/// `FBIOGET_FSCREENINFO` — linux/fb.h
const FBIOGET_FSCREENINFO: libc::Ioctl = 0x4602 as libc::Ioctl;

#[repr(C)]
#[derive(Clone, Copy)]
struct FbBitfield {
    offset: u32,
    length: u32,
    msb_right: u32,
}

/// Layout matches linux `struct fb_var_screeninfo` on x86_64 (160 bytes).
#[repr(C)]
struct FbVarScreeninfo {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: FbBitfield,
    green: FbBitfield,
    blue: FbBitfield,
    transp: FbBitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [u32; 4],
}

/// Layout matches linux `struct fb_fix_screeninfo` on x86_64 (80 bytes).
#[repr(C)]
struct FbFixScreeninfo {
    id: [u8; 16],
    smem_start: usize,
    smem_len: u32,
    type_: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    _pad_to_line_length: u16,
    line_length: u32,
    mmio_start: usize,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [u16; 2],
}

const _: () = assert!(mem::size_of::<FbVarScreeninfo>() == 160);
const _: () = assert!(mem::size_of::<FbFixScreeninfo>() == 80);

fn ioctl_get_var(file: &File) -> io::Result<FbVarScreeninfo> {
    let mut var = unsafe { mem::zeroed::<FbVarScreeninfo>() };
    let rc = unsafe { libc::ioctl(file.as_raw_fd(), FBIOGET_VSCREENINFO, &mut var) };
    if rc < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(var)
}

fn ioctl_get_fix(file: &File) -> io::Result<FbFixScreeninfo> {
    let mut fix = unsafe { mem::zeroed::<FbFixScreeninfo>() };
    let rc = unsafe { libc::ioctl(file.as_raw_fd(), FBIOGET_FSCREENINFO, &mut fix) };
    if rc < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(fix)
}

/// Prefer ioctl geometry; fall back to caller-supplied sysfs geometry.
pub fn resolve_fb_plan(file: &File, sysfs_geom: &FbGeometry) -> Result<FbMapPlan, String> {
    match (ioctl_get_var(file), ioctl_get_fix(file)) {
        (Ok(var), Ok(fix)) => {
            let id = String::from_utf8_lossy(&fix.id)
                .trim_end_matches('\0')
                .to_string();
            let geom = FbGeometry {
                width: var.xres,
                height: var.yres,
                bpp: var.bits_per_pixel,
                stride: fix.line_length,
            };
            eprintln!(
                "{DEMO_IDENTITY}: ioctl geometry id={id:?} {}x{} bpp={} stride={} smem_len={} \
                 (sysfs was {}x{} bpp={} stride={})",
                geom.width,
                geom.height,
                geom.bpp,
                geom.stride,
                fix.smem_len,
                sysfs_geom.width,
                sysfs_geom.height,
                sysfs_geom.bpp,
                sysfs_geom.stride
            );
            validate_fb_geometry(geom, Some(fix.smem_len), "ioctl")
        }
        (var_res, fix_res) => {
            let var_msg = match &var_res {
                Ok(_) => "ok".to_string(),
                Err(e) => e.to_string(),
            };
            let fix_msg = match &fix_res {
                Ok(_) => "ok".to_string(),
                Err(e) => e.to_string(),
            };
            eprintln!(
                "{DEMO_IDENTITY}: ioctl FBIOGET_* unavailable (var={var_msg}; fix={fix_msg}); \
                 falling back to sysfs geometry"
            );
            validate_fb_geometry(sysfs_geom.clone(), None, "sysfs")
        }
    }
}

/// Map `/dev/fb0` with an **explicit** validated length (never file-size mmap).
pub fn map_fb_explicit(file: &File, plan: &FbMapPlan) -> Result<MmapMut, String> {
    let file_len = file.metadata().map(|m| m.len()).unwrap_or(0);
    eprintln!(
        "{DEMO_IDENTITY}: mmap plan source={} requested_len={} visible={} \
         format={}x{} bpp={} stride={} file_stat_len={} (char-dev often 0)",
        plan.source,
        plan.map_len,
        plan.visible_bytes,
        plan.geom.width,
        plan.geom.height,
        plan.geom.bpp,
        plan.geom.stride,
        file_len
    );
    // SAFETY: map_len was validated against geometry / smem_len; file is R/W fb0.
    // We never write past `visible_bytes` in the blit path.
    let mmap = unsafe {
        MmapOptions::new()
            .len(plan.map_len)
            .map_mut(file)
            .map_err(|e| {
                format!(
                    "{DEMO_IDENTITY}: mmap failed requested_len={} file_stat_len={file_len}: {e}",
                    plan.map_len
                )
            })?
    };
    let obtained = mmap.len();
    eprintln!("{DEMO_IDENTITY}: mmap obtained_len={obtained}");
    if obtained < plan.visible_bytes {
        return Err(format!(
            "{DEMO_IDENTITY}: mmap obtained_len={obtained} < visible={} \
             (requested={})",
            plan.visible_bytes, plan.map_len
        ));
    }
    Ok(mmap)
}
