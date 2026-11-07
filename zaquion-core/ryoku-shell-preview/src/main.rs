//! Guest entry for `ryoku-shell-preview` (Mission 015).
//!
//! Reuses Mission 014.2 explicit fb0 mmap. Shell chrome is illustrative —
//! input is Mission 015.1 (**NOT_RUN**). Graphical guest confirm is separate.

#![allow(unsafe_code)]

mod fb_mmap;

use std::process::ExitCode;

use ryoku_graphics_demo::{
    classify_no_fb_reason, format_outcome, graphics_root_from_env, open_fb_rw, probe_fb0,
};
use ryoku_shell_preview::{present_shell, render_shell, SHELL_IDENTITY};

fn main() -> ExitCode {
    let root = match graphics_root_from_env() {
        Ok(p) => p,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(2);
        }
    };

    eprintln!(
        "{SHELL_IDENTITY}: starting shell preview under {}",
        root.display()
    );
    eprintln!("{SHELL_IDENTITY}: input/evdev = NOT_RUN (Mission 015.1); chrome is illustrative");

    let (fb_path, sysfs_geom) = match probe_fb0(&root) {
        Ok(v) => v,
        Err(reason) => {
            // Serial fallback honesty — no FB fight, no fake present.
            eprint!("{}", format_outcome(&classify_no_fb_reason(reason)));
            eprintln!("{SHELL_IDENTITY}: serial fallback — shell not presented");
            return ExitCode::from(1);
        }
    };

    let file = match open_fb_rw(&fb_path) {
        Ok(f) => f,
        Err(err) => {
            eprintln!("{SHELL_IDENTITY}: open {} failed: {err}", fb_path.display());
            return ExitCode::from(1);
        }
    };

    let plan = match fb_mmap::resolve_fb_plan(&file, &sysfs_geom) {
        Ok(p) => p,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(1);
        }
    };

    let (buf, layout) = match render_shell(plan.geom.width, plan.geom.height) {
        Ok(v) => v,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(1);
        }
    };
    eprintln!(
        "{SHELL_IDENTITY}: layout panel_h={} dock={}x{} at ({},{}) desktop_h={}",
        layout.panel_h,
        layout.dock_w,
        layout.dock_h,
        layout.dock_x,
        layout.dock_y,
        layout.desktop_h
    );

    let mut mmap = match fb_mmap::map_fb_explicit(&file, &plan) {
        Ok(m) => m,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(1);
        }
    };

    match present_shell(&mut mmap, &plan.geom, &buf) {
        Ok(()) => {
            let _ = mmap.flush();
            println!(
                "{SHELL_IDENTITY}: presented shell layout into /dev/fb0 ({}x{} bpp={}); \
                 visual shell guest still NOT_RUN until human confirm; input NOT_RUN (015.1)",
                plan.geom.width, plan.geom.height, plan.geom.bpp
            );
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}
