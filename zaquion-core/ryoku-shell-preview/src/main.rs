//! Guest entry for `ryoku-shell-preview` (Mission 015 / 015.2 / **015.2.1**).
//!
//! 015.2.1: no visible fb clear; scanline/dirty blit; coalesce motion; keep all
//! keyboards; configurable FPS; render metrics. `EVENTS RECEIVED` is a fact
//! indicator only — not a claim of functional click/nav.

#![allow(unsafe_code)]

mod fb_mmap;
mod input;

use std::env;
use std::process::ExitCode;
use std::thread;
use std::time::{Duration, Instant};

use ryoku_graphics_demo::RgbBuffer;
use ryoku_graphics_demo::{
    classify_no_fb_reason, format_outcome, graphics_root_from_env, open_fb_rw, probe_fb0,
};
use ryoku_shell_preview::{
    compose_shell_interactive, dirty_band_for_cursor, merge_dirty, present_shell,
    present_shell_rows, AdaptiveProfile, InputFact, InteractiveState, ShellLayout, SHELL_IDENTITY,
};

use crate::input::{
    coalesce_actions, scan_evdev_devices, EvdevDevice, InputAction, RedrawGate, BTN_LEFT,
    BTN_TOUCH, KEY_DOWN, KEY_ENTER, KEY_ESC, KEY_F1, KEY_F2, KEY_F3, KEY_LEFT, KEY_RIGHT,
    KEY_SPACE, KEY_TAB, KEY_UP,
};

#[derive(Debug, Default)]
struct RenderMetrics {
    frames: u64,
    compose_ns: u128,
    blit_ns: u128,
    scratch_bytes: usize,
    last_report: Option<Instant>,
}

impl RenderMetrics {
    fn note(&mut self, compose: Duration, blit: Duration, scratch_bytes: usize) {
        self.frames = self.frames.saturating_add(1);
        self.compose_ns = self.compose_ns.saturating_add(compose.as_nanos());
        self.blit_ns = self.blit_ns.saturating_add(blit.as_nanos());
        self.scratch_bytes = scratch_bytes;
        let now = Instant::now();
        let due = match self.last_report {
            None => true,
            Some(t) => now.duration_since(t) >= Duration::from_secs(5),
        };
        if due && self.frames > 0 {
            let avg_c = self.compose_ns / u128::from(self.frames);
            let avg_b = self.blit_ns / u128::from(self.frames);
            eprintln!(
                "{SHELL_IDENTITY}: metrics frames={} avg_compose_us={} avg_blit_us={} scratch_kib={}",
                self.frames,
                avg_c / 1000,
                avg_b / 1000,
                self.scratch_bytes / 1024
            );
            self.last_report = Some(now);
            self.frames = 0;
            self.compose_ns = 0;
            self.blit_ns = 0;
        }
    }
}

fn target_fps(profile: AdaptiveProfile) -> u32 {
    env::var("RYOKU_SHELL_TARGET_FPS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or_else(|| profile.target_fps())
        .clamp(1, 120)
}

fn profile_from_env() -> AdaptiveProfile {
    env::var("RYOKU_DESKTOP_PROFILE")
        .ok()
        .and_then(|s| AdaptiveProfile::parse(&s))
        .unwrap_or(AdaptiveProfile::Balanced)
}

fn input_diag() -> bool {
    matches!(
        env::var("RYOKU_SHELL_INPUT_DIAG").as_deref(),
        Ok("1") | Ok("true") | Ok("TRUE")
    )
}

/// Apply button/key after motion. Returns `(visual_changed, functional_click_or_key)`.
fn apply_discrete(
    layout: &ShellLayout,
    ui: &mut InteractiveState,
    action: &InputAction,
    diag: bool,
) -> (bool, bool) {
    match *action {
        InputAction::Button { code, pressed } => {
            if matches!(code, BTN_LEFT | BTN_TOUCH) {
                if diag {
                    eprintln!(
                        "{SHELL_IDENTITY}: diag button code={code} pressed={pressed} at ({},{}) launcher={}",
                        ui.cursor_x, ui.cursor_y, ui.launcher_open
                    );
                }
                if pressed {
                    let before = ui.launcher_open;
                    ui.on_primary_press(layout);
                    if diag && ui.launcher_open != before {
                        eprintln!(
                            "{SHELL_IDENTITY}: diag launcher_open -> {}",
                            ui.launcher_open
                        );
                    }
                } else {
                    ui.on_primary_release();
                }
                (true, true)
            } else {
                (false, false)
            }
        }
        InputAction::Key { code, pressed } => {
            if !pressed {
                return (false, false);
            }
            if diag {
                eprintln!("{SHELL_IDENTITY}: diag key code={code}");
            }
            // Mission 016: F1/F2/F3 switch profile (session); Ultra = arch fallback.
            if matches!(code, KEY_F1 | KEY_F2 | KEY_F3) {
                let next = match code {
                    KEY_F1 => AdaptiveProfile::Lite,
                    KEY_F2 => AdaptiveProfile::Balanced,
                    _ => AdaptiveProfile::Ultra,
                };
                ui.set_profile(next);
                eprintln!(
                    "{SHELL_IDENTITY}: profile -> {} (effective={}) anim={} fps={}",
                    next.name(),
                    next.effective().name(),
                    next.animation_policy(),
                    next.target_fps()
                );
                return (true, true);
            }
            let visual = if ui.launcher_open {
                match code {
                    KEY_ESC => {
                        ui.close_launcher();
                        true
                    }
                    KEY_UP | KEY_LEFT => {
                        ui.nav_launcher(-1);
                        true
                    }
                    KEY_DOWN | KEY_RIGHT | KEY_TAB => {
                        ui.nav_launcher(1);
                        true
                    }
                    KEY_ENTER | KEY_SPACE => {
                        ui.activate_selected();
                        true
                    }
                    _ => false,
                }
            } else {
                match code {
                    KEY_ESC => {
                        ui.close_launcher();
                        true
                    }
                    KEY_LEFT | KEY_UP => {
                        ui.nav_dock(layout, -1);
                        true
                    }
                    KEY_RIGHT | KEY_TAB | KEY_DOWN => {
                        ui.nav_dock(layout, 1);
                        true
                    }
                    KEY_ENTER | KEY_SPACE => {
                        ui.activate_selected();
                        true
                    }
                    _ => false,
                }
            };
            (visual, visual)
        }
        _ => (false, false),
    }
}

fn present_dirty(
    mmap: &mut memmap2::MmapMut,
    geom: &ryoku_graphics_demo::FbGeometry,
    layout: &ShellLayout,
    ui: &InteractiveState,
    scratch: &mut RgbBuffer,
    dirty: Option<(u32, u32)>,
    metrics: &mut RenderMetrics,
) -> Result<(), String> {
    let t0 = Instant::now();
    compose_shell_interactive(scratch, layout, Some(ui));
    let t1 = Instant::now();
    match dirty {
        Some((y0, y1)) if y1 > y0 && (y1 - y0) < layout.height => {
            present_shell_rows(mmap, geom, scratch, y0, y1)?;
        }
        _ => {
            present_shell(mmap, geom, scratch)?;
        }
    }
    // flush is best-effort mmap sync — **not** vblank / pageflip (fbdev).
    let _ = mmap.flush();
    let t2 = Instant::now();
    metrics.note(t1 - t0, t2 - t1, scratch.pixels.len());
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
    let mut fps = target_fps(ui.profile);
    let mut gate = RedrawGate::from_fps(fps);
    let mut dirty = true;
    let mut full_dirty = true;
    let mut dirty_y = (0u32, layout.height);
    let mut metrics = RenderMetrics::default();
    let fb_w = layout.width as i32;
    let fb_h = layout.height as i32;
    let diag = input_diag();
    let mut prev_cursor = (ui.cursor_x, ui.cursor_y);
    let mut prev_launcher = ui.launcher_open;
    let mut prev_focus = ui.launcher_focus;
    let mut prev_hover = ui.hover_dock;
    let mut prev_selected = ui.selected_dock;
    let mut prev_profile = ui.profile;

    eprintln!(
        "{SHELL_IDENTITY}: event loop 016 adaptive fps={fps} profile={} diag={diag}; \
         no continuous redraw; EVENTS RECEIVED ≠ click; GUEST_NOT_RUN — fact={:?}",
        ui.profile.name(),
        ui.input_fact
    );

    loop {
        let mut raw = Vec::new();
        for dev in devices.iter_mut() {
            raw.extend(dev.poll_actions(fb_w, fb_h));
        }

        let mut visual = false;
        if !raw.is_empty() {
            // Fact: events arrived. Not a PASS and not "click worked".
            ui.input_fact.note_event();

            let (motion, discrete) = coalesce_actions(&raw);
            if motion.has_motion() {
                let old = (ui.cursor_x, ui.cursor_y);
                if motion.abs_x.is_some() || motion.abs_y.is_some() {
                    ui.move_abs(
                        layout,
                        motion.abs_x.unwrap_or(ui.cursor_x),
                        motion.abs_y.unwrap_or(ui.cursor_y),
                    );
                }
                if motion.rel_dx != 0 || motion.rel_dy != 0 {
                    ui.move_by(layout, motion.rel_dx, motion.rel_dy);
                }
                if (ui.cursor_x, ui.cursor_y) != old {
                    visual = true;
                    let a = dirty_band_for_cursor(old.1, layout.height);
                    let b = dirty_band_for_cursor(ui.cursor_y, layout.height);
                    dirty_y = merge_dirty(dirty_y, merge_dirty(a, b));
                }
            }
            for a in &discrete {
                let (v, functional) = apply_discrete(layout, ui, a, diag);
                if v {
                    visual = true;
                    full_dirty = true; // launcher/dock chrome may change widely
                }
                if functional && diag {
                    eprintln!("{SHELL_IDENTITY}: diag functional interaction (not PASS_MANUAL)");
                }
            }
        }

        if ui.launcher_open != prev_launcher
            || ui.launcher_focus != prev_focus
            || ui.hover_dock != prev_hover
            || ui.selected_dock != prev_selected
            || ui.profile != prev_profile
        {
            visual = true;
            full_dirty = true;
        }
        if ui.profile != prev_profile {
            fps = target_fps(ui.profile);
            gate = RedrawGate::from_fps(fps);
            prev_profile = ui.profile;
        }
        if (ui.cursor_x, ui.cursor_y) != prev_cursor {
            visual = true;
        }

        if visual {
            dirty = true;
        }

        // Never continuous redraw: idle sleeps without present.
        if dirty && gate.allow() {
            let band = if full_dirty { None } else { Some(dirty_y) };
            if let Err(err) = present_dirty(mmap, geom, layout, ui, scratch, band, &mut metrics) {
                eprintln!("{SHELL_IDENTITY}: WARN redraw failed: {err}");
            }
            dirty = false;
            full_dirty = false;
            dirty_y = (0, 0);
            prev_cursor = (ui.cursor_x, ui.cursor_y);
            prev_launcher = ui.launcher_open;
            prev_focus = ui.launcher_focus;
            prev_hover = ui.hover_dock;
            prev_selected = ui.selected_dock;
        }

        // Idle: no redraw. Sleep avoids busy-loop / rest CPU thrash.
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
        "{SHELL_IDENTITY}: starting adaptive shell under {} (Mission 016)",
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
    ui.set_profile(profile_from_env());
    let mut scratch = RgbBuffer::new(layout.width, layout.height, ryoku_shell_preview::COLOR_NAVY);

    eprintln!(
        "{SHELL_IDENTITY}: layout panel_h={} dock={}x{} at ({},{}) desktop_h={} fb={}x{} stride={} profile={}",
        layout.panel_h,
        layout.dock_w,
        layout.dock_h,
        layout.dock_x,
        layout.dock_y,
        layout.desktop_h,
        plan.geom.width,
        plan.geom.height,
        plan.geom.stride,
        ui.profile.name()
    );

    let mut mmap = match fb_mmap::map_fb_explicit(&file, &plan) {
        Ok(m) => m,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(1);
        }
    };

    let mut devices = match scan_evdev_devices(&root) {
        Ok((d, fact)) => {
            ui.input_fact = fact;
            d
        }
        Err(warn) => {
            eprintln!("{warn}");
            eprintln!(
                "{SHELL_IDENTITY}: WARN continuing without guest input — serial console still OK"
            );
            ui.input_fact = InputFact::Unavailable;
            Vec::new()
        }
    };

    let mut metrics = RenderMetrics::default();
    if let Err(err) = present_dirty(
        &mut mmap,
        &plan.geom,
        &layout,
        &ui,
        &mut scratch,
        None,
        &mut metrics,
    ) {
        eprintln!("{err}");
        return ExitCode::from(1);
    }
    println!(
        "{SHELL_IDENTITY}: presented shell+launcher into /dev/fb0 ({}x{} bpp={}); fact={:?}; staying alive (015.2.1 no-clear blit)",
        plan.geom.width, plan.geom.height, plan.geom.bpp, ui.input_fact
    );

    event_loop(
        &mut mmap,
        &plan.geom,
        &layout,
        &mut ui,
        &mut devices,
        &mut scratch,
    );
}
