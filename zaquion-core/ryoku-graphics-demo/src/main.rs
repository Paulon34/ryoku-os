//! Guest/host entry for `ryoku-graphics-demo` (Mission 014 / 014.1 / 014.2).
//!
//! Unsafe is isolated in [`fb_mmap`]: ioctl geometry + explicit-length mmap.
//! Library code stays `forbid(unsafe_code)`. Prefers real fb0. DRM-only → honest fail.
//!
//! Creating a software title buffer is **not** a present. `FIRST_PIXELS` never auto-PASS.

#![allow(unsafe_code)]

mod fb_mmap;

use std::process::ExitCode;

use ryoku_graphics_demo::{
    classify_no_fb_reason, format_outcome, format_surface_probe, graphics_root_from_env,
    open_fb_rw, probe_fb0, probe_surfaces, render_title, PresentOutcome, RgbBuffer,
};

fn main() -> ExitCode {
    let root = match graphics_root_from_env() {
        Ok(p) => p,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(2);
        }
    };

    eprintln!(
        "ryoku-graphics-demo: device discovered / surface inventory under {}",
        root.display()
    );
    let surfaces = probe_surfaces(&root);
    eprint!("{}", format_surface_probe(&surfaces));

    let (fb_path, sysfs_geom) = match probe_fb0(&root) {
        Ok(v) => v,
        Err(reason) => {
            // Still honest: software title alone is NOT a present.
            let soft = PresentOutcome::SoftwareOnly {
                width: 640,
                height: 480,
            };
            eprint!("{}", format_outcome(&soft));
            let out = classify_no_fb_reason(reason);
            eprint!("{}", format_outcome(&out));
            return ExitCode::from(1);
        }
    };

    eprintln!(
        "ryoku-graphics-demo: surface available (sysfs): {} ({}x{} bpp={} stride={})",
        fb_path.display(),
        sysfs_geom.width,
        sysfs_geom.height,
        sysfs_geom.bpp,
        sysfs_geom.stride
    );

    let file = match open_fb_rw(&fb_path) {
        Ok(f) => f,
        Err(err) => {
            let out = PresentOutcome::NoSurface {
                reason: format!(
                    "ryoku-graphics-demo: open {} failed: {err}",
                    fb_path.display()
                ),
            };
            eprint!("{}", format_outcome(&out));
            return ExitCode::from(1);
        }
    };

    let plan = match fb_mmap::resolve_fb_plan(&file, &sysfs_geom) {
        Ok(p) => p,
        Err(err) => {
            let out = PresentOutcome::NoSurface { reason: err };
            eprint!("{}", format_outcome(&out));
            return ExitCode::from(1);
        }
    };

    // Software buffer matches FB size so non-640×480 modes (e.g. 941×474) get a
    // full-surface title. Buffer creation alone is still NOT a present.
    let mut buf = RgbBuffer::new(plan.geom.width, plan.geom.height, (0, 0, 0));
    render_title(&mut buf);
    eprint!(
        "{}",
        format_outcome(&PresentOutcome::SoftwareOnly {
            width: buf.width,
            height: buf.height,
        })
    );

    let mut mmap = match fb_mmap::map_fb_explicit(&file, &plan) {
        Ok(m) => m,
        Err(err) => {
            let out = PresentOutcome::NoSurface { reason: err };
            eprint!("{}", format_outcome(&out));
            return ExitCode::from(1);
        }
    };

    match ryoku_graphics_demo::present_to_mmap(&mut mmap, &plan.geom, &buf) {
        Ok(()) => {
            if let Err(err) = mmap.flush() {
                let out = PresentOutcome::NoSurface {
                    reason: format!("ryoku-graphics-demo: flush after blit failed: {err}"),
                };
                eprint!("{}", format_outcome(&out));
                return ExitCode::from(1);
            }
            let out = PresentOutcome::Fb0Presented {
                width: plan.geom.width,
                height: plan.geom.height,
                bpp: plan.geom.bpp,
            };
            print!("{}", format_outcome(&out));
            ExitCode::SUCCESS
        }
        Err(err) => {
            let out = PresentOutcome::NoSurface {
                reason: format!(
                    "ryoku-graphics-demo: blit failed: {err} \
                     (map_len={} visible={} format={}x{} bpp={} stride={})",
                    mmap.len(),
                    plan.visible_bytes,
                    plan.geom.width,
                    plan.geom.height,
                    plan.geom.bpp,
                    plan.geom.stride
                ),
            };
            eprint!("{}", format_outcome(&out));
            ExitCode::from(1)
        }
    }
}
