//! Host-side REPL for `ryoku-console` (Mission 011 prep).
//!
//! Not PID 1. Not a guest boot. Exit cleanly on EOF (Ctrl-D).

#![forbid(unsafe_code)]

use std::io::{self, BufRead, Write};
use std::process::ExitCode;

use ryoku_console::{eval_line, startup_banner, ParseError, MAX_LINE_BYTES, PROMPT};

fn main() -> ExitCode {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let _ = write!(stdout, "{}", startup_banner(env!("CARGO_PKG_VERSION")));
    let _ = write!(stdout, "{PROMPT}");
    let _ = stdout.flush();

    for line in stdin.lock().lines() {
        let Ok(line) = line else {
            let _ = writeln!(stdout);
            return ExitCode::from(1);
        };

        // Enforce line cap at the REPL boundary (BufRead can yield huge lines).
        if line.len() > MAX_LINE_BYTES {
            let _ = writeln!(stdout, "error: {}", ParseError::TooLong { len: line.len() });
        } else {
            match eval_line(&line) {
                Ok(out) => {
                    let _ = write!(stdout, "{out}");
                }
                Err(err) => {
                    let _ = writeln!(stdout, "error: {err}");
                }
            }
        }

        let _ = write!(stdout, "{PROMPT}");
        let _ = stdout.flush();
    }

    // EOF: drop trailing prompt noise with a newline, then exit 0.
    let _ = writeln!(stdout);
    ExitCode::SUCCESS
}
