//! Guest/host entry for `ryoku-graphics-demo` (Mission 014 / 014.1).
//!
//! `mmap` of `/dev/fb0` requires a single unsafe call via `memmap2`; library
//! code stays `forbid(unsafe_code)`. Prefers real fb0. DRM-only → honest fail.

#![allow(unsafe_code)]

use std::process::ExitCode;

use memmap2::MmapMut;
use ryoku_graphics_demo::{
    classify_no_fb_reason, format_outcome, format_surface_probe, graphics_root_from_env,
    open_fb_rw, present_to_mmap, probe_fb0, probe_surfaces, render_title, PresentOutcome,
    RgbBuffer,
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

    let mut buf = RgbBuffer::new(640, 480, (0, 0, 0));
    render_title(&mut buf);

    let (fb_path, geom) = match probe_fb0(&root) {
        Ok(v) => v,
        Err(reason) => {
            let out = classify_no_fb_reason(reason);
            eprint!("{}", format_outcome(&out));
            return ExitCode::from(1);
        }
    };

    eprintln!(
        "ryoku-graphics-demo: surface available: {} ({}x{} bpp={} stride={})",
        fb_path.display(),
        geom.width,
        geom.height,
        geom.bpp,
        geom.stride
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

    // SAFETY: file is opened R/W; size comes from fb driver mmap. We only write
    // within stride*height checked by `present_to_mmap`.
    let mut mmap = match unsafe { MmapMut::map_mut(&file) } {
        Ok(m) => m,
        Err(err) => {
            let out = PresentOutcome::NoSurface {
                reason: format!(
                    "ryoku-graphics-demo: mmap {} failed: {err}",
                    fb_path.display()
                ),
            };
            eprint!("{}", format_outcome(&out));
            return ExitCode::from(1);
        }
    };

    match present_to_mmap(&mut mmap, &geom, &buf) {
        Ok(()) => {
            let _ = mmap.flush();
            let out = PresentOutcome::Fb0Presented {
                width: geom.width,
                height: geom.height,
                bpp: geom.bpp,
            };
            print!("{}", format_outcome(&out));
            ExitCode::SUCCESS
        }
        Err(err) => {
            let out = PresentOutcome::NoSurface {
                reason: format!("ryoku-graphics-demo: blit failed: {err}"),
            };
            eprint!("{}", format_outcome(&out));
            ExitCode::from(1)
        }
    }
}
