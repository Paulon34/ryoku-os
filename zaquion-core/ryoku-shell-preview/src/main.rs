//! Guest entry for `ryoku-shell-preview` (Mission 015 / 015.1).
//!
//! Reuses Mission 014.2 explicit fb0 mmap. Mission 015.1 keeps the shell alive
//! with a guest-evdev event loop (mouse + keyboard). Guest interaction statuses
//! stay **NOT_RUN** until human confirm — never invented from host CI.

#![allow(unsafe_code)]

mod fb_mmap;
mod input;

use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use ryoku_graphics_demo::RgbBuffer;
use ryoku_graphics_demo::{
    classify_no_fb_reason, format_outcome, graphics_root_from_env, open_fb_rw, probe_fb0,
};
use ryoku_shell_preview::{
    compose_shell_interactive, present_shell, InteractiveState, ShellLayout, SHELL_IDENTITY,
};

use crate::input::{
    scan_evdev_devices, EvdevDevice, InputAction, RedrawGate, BTN_LEFT, BTN_TOUCH, KEY_DOWN,
    KEY_ENTER, KEY_ESC, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_TAB, KEY_UP,
};

fn apply_action(layout: &ShellLayout, ui: &mut InteractiveState, action: InputAction) -> bool {
    match action {
        InputAction::AbsSample { x, y } => {
            let nx = x.unwrap_or(ui.cursor_x);
            let ny = y.unwrap_or(ui.cursor_y);
            ui.move_abs(layout, nx, ny);
            true
        }
        InputAction::RelDelta { dx, dy } => {
            if dx != 0 || dy != 0 {
                ui.move_by(layout, dx, dy);
                true
            } else {
                false
            }
        }
        InputAction::Button { code, pressed } => {
            if matches!(code, BTN_LEFT | BTN_TOUCH) {
                if pressed {
                    ui.on_primary_press(layout);
                } else {
                    ui.on_primary_release();
                }
                true
            } else {
                false
            }
        }
        InputAction::Key { code, pressed } => {
            if !pressed {
                return false;
            }
            match code {
                KEY_ESC => {
                    ui.close_launcher();
                    true
                }
                KEY_LEFT => {
                    ui.nav_dock(layout, -1);
                    true
                }
                KEY_RIGHT | KEY_TAB => {
                    ui.nav_dock(layout, 1);
                    true
                }
                KEY_UP => {
                    ui.nav_dock(layout, -1);
                    true
                }
                KEY_DOWN => {
                    ui.nav_dock(layout, 1);
                    true
                }
                KEY_ENTER | KEY_SPACE => {
                    ui.activate_selected();
                    true
                }
                _ => false,
            }
        }
    }
}

fn present_ui(
    mmap: &mut memmap2::MmapMut,
    geom: &ryoku_graphics_demo::FbGeometry,
    layout: &ShellLayout,
    ui: &InteractiveState,
    scratch: &mut RgbBuffer,
) -> Result<(), String> {
    compose_shell_interactive(scratch, layout, Some(ui));
    present_shell(mmap, geom, scratch)?;
    let _ = mmap.flush();
    Ok(())
}

fn event_loop(
    mmap: &mut memmap2::MmapMut,
    geom: &ryoku_graphics_demo::FbGeometry,
    layout: &ShellLayout,
    ui: &mut InteractiveState,
    devices: &mut [EvdevDevice],
    scratch: &mut RgbBuffer,
) -> ! {
    let mut gate = RedrawGate::new(Duration::from_millis(16));
    let mut dirty = true;
    let fb_w = layout.width as i32;
    let fb_h = layout.height as i32;

    eprintln!(
        "{SHELL_IDENTITY}: event loop running (guest evdev); \
         INPUT_GUEST/MOUSE_INTERACTION/KEYBOARD_INTERACTION=NOT_RUN until manual"
    );

    loop {
        let mut changed = false;
        for dev in devices.iter_mut() {
            for action in dev.poll_actions(fb_w, fb_h) {
                if apply_action(layout, ui, action) {
                    changed = true;
                }
            }
        }
        if changed {
            dirty = true;
        }
        if dirty && gate.allow() {
            if let Err(err) = present_ui(mmap, geom, layout, ui, scratch) {
                eprintln!("{SHELL_IDENTITY}: WARN redraw failed: {err}");
            }
            dirty = false;
        }
        // No busy-loop: sleep even when idle.
        thread::sleep(Duration::from_millis(8));
    }
}

fn main() -> ExitCode {
    let root = match graphics_root_from_env() {
        Ok(p) => p,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(2);
        }
    };

    eprintln!(
        "{SHELL_IDENTITY}: starting interactive shell under {} (Mission 015.1)",
        root.display()
    );

    let (fb_path, sysfs_geom) = match probe_fb0(&root) {
        Ok(v) => v,
        Err(reason) => {
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

    let layout = match ShellLayout::for_fb(plan.geom.width, plan.geom.height) {
        Ok(l) => l,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(1);
        }
    };
    let mut ui = InteractiveState::new(&layout);
    let mut scratch = RgbBuffer::new(layout.width, layout.height, ryoku_shell_preview::COLOR_NAVY);

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

    if let Err(err) = present_ui(&mut mmap, &plan.geom, &layout, &ui, &mut scratch) {
        eprintln!("{err}");
        return ExitCode::from(1);
    }
    println!(
        "{SHELL_IDENTITY}: presented shell layout into /dev/fb0 ({}x{} bpp={}); staying alive",
        plan.geom.width, plan.geom.height, plan.geom.bpp
    );

    let mut devices = match scan_evdev_devices(&root) {
        Ok(d) => d,
        Err(warn) => {
            // Fallback: WARN + serial honesty; shell stays alive on FB without input.
            eprintln!("{warn}");
            eprintln!(
                "{SHELL_IDENTITY}: WARN continuing without guest input — serial console still OK"
            );
            Vec::new()
        }
    };

    // Lives forever: PID1 runs serial console in parallel (015.1).
    event_loop(
        &mut mmap,
        &plan.geom,
        &layout,
        &mut ui,
        &mut devices,
        &mut scratch,
    );
}
