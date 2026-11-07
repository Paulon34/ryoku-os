//! Isolated unsafe: reuse Mission 014.2 ioctl + explicit-length mmap for shell.

#![allow(unsafe_code)]

use std::fs::File;
use std::io;
use std::mem;
use std::os::fd::AsRawFd;

use memmap2::{MmapMut, MmapOptions};
use ryoku_graphics_demo::{validate_fb_geometry, FbGeometry, FbMapPlan};
use ryoku_shell_preview::SHELL_IDENTITY;

const FBIOGET_VSCREENINFO: libc::Ioctl = 0x4600 as libc::Ioctl;
const FBIOGET_FSCREENINFO: libc::Ioctl = 0x4602 as libc::Ioctl;

#[repr(C)]
#[derive(Clone, Copy)]
struct FbBitfield {
    offset: u32,
    length: u32,
    msb_right: u32,
}

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

pub fn resolve_fb_plan(file: &File, sysfs_geom: &FbGeometry) -> Result<FbMapPlan, String> {
    match (ioctl_get_var(file), ioctl_get_fix(file)) {
        (Ok(var), Ok(fix)) => {
            let geom = FbGeometry {
                width: var.xres,
                height: var.yres,
                bpp: var.bits_per_pixel,
                stride: fix.line_length,
            };
            eprintln!(
                "{SHELL_IDENTITY}: ioctl geometry {}x{} bpp={} stride={} smem_len={}",
                geom.width, geom.height, geom.bpp, geom.stride, fix.smem_len
            );
            validate_fb_geometry(geom, Some(fix.smem_len), "ioctl")
        }
        _ => {
            eprintln!("{SHELL_IDENTITY}: ioctl unavailable; falling back to sysfs geometry");
            validate_fb_geometry(sysfs_geom.clone(), None, "sysfs")
        }
    }
}

pub fn map_fb_explicit(file: &File, plan: &FbMapPlan) -> Result<MmapMut, String> {
    let file_len = file.metadata().map(|m| m.len()).unwrap_or(0);
    eprintln!(
        "{SHELL_IDENTITY}: mmap requested_len={} visible={} file_stat_len={file_len}",
        plan.map_len, plan.visible_bytes
    );
    let mmap = unsafe {
        MmapOptions::new()
            .len(plan.map_len)
            .map_mut(file)
            .map_err(|e| format!("{SHELL_IDENTITY}: mmap failed: {e}"))?
    };
    eprintln!("{SHELL_IDENTITY}: mmap obtained_len={}", mmap.len());
    if mmap.len() < plan.visible_bytes {
        return Err(format!(
            "{SHELL_IDENTITY}: mmap obtained_len={} < visible={}",
            mmap.len(),
            plan.visible_bytes
        ));
    }
    Ok(mmap)
}
