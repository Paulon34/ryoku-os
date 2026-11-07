//! Host-side REPL for `ryoku-console` (Mission 011 prep).
//!
//! Not PID 1. Not a guest boot. Exit on EOF or Ctrl-D.

#![forbid(unsafe_code)]

use std::io::{self, BufRead, Write};
use std::process::ExitCode;

use ryoku_console::{eval_line, PROMPT};

fn main() -> ExitCode {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let _ = writeln!(
        stdout,
        "ryoku-console {} — limited builtins; not a product OS shell",
        env!("CARGO_PKG_VERSION")
    );
    let _ = writeln!(
        stdout,
        "Separate from ryoku-init PID 1 / RYOKU_BOOT_SEED_READY. Type `help`."
    );
    let _ = stdout.flush();

    for line in stdin.lock().lines() {
        let Ok(line) = line else {
            return ExitCode::from(1);
        };
        match eval_line(&line) {
            Ok(out) => {
                let _ = write!(stdout, "{out}");
            }
            Err(err) => {
                let _ = writeln!(stdout, "error: {err}");
            }
        }
        let _ = write!(stdout, "{PROMPT}");
        let _ = stdout.flush();
    }
    ExitCode::SUCCESS
}
