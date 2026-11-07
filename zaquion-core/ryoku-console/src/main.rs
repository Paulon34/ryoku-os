//! Host-side REPL for `ryoku-console` (Mission 011 prep).
//!
//! Not PID 1. Not a guest boot. Exit cleanly on EOF (Ctrl-D).
//! Line I/O uses capped [`ryoku_console::read_limited_line`] (fill_buf/consume).

#![forbid(unsafe_code)]

use std::io::{self, Write};
use std::process::ExitCode;

use ryoku_console::{
    eval_line, read_limited_line, startup_banner, LimitedLine, ParseError, PROMPT,
};

fn main() -> ExitCode {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut input = stdin.lock();

    let _ = write!(stdout, "{}", startup_banner(env!("CARGO_PKG_VERSION")));
    let _ = write!(stdout, "{PROMPT}");
    let _ = stdout.flush();

    loop {
        match read_limited_line(&mut input) {
            Ok(LimitedLine::Eof) => {
                let _ = writeln!(stdout);
                return ExitCode::SUCCESS;
            }
            Ok(LimitedLine::TooLong { observed }) => {
                let _ = writeln!(stdout, "error: {}", ParseError::TooLong { len: observed });
            }
            Ok(LimitedLine::Line(line)) => match eval_line(&line) {
                Ok(out) => {
                    let _ = write!(stdout, "{out}");
                }
                Err(err) => {
                    let _ = writeln!(stdout, "error: {err}");
                }
            },
            Err(err) => {
                let _ = writeln!(stdout, "error: io: {err}");
                let _ = writeln!(stdout);
                return ExitCode::from(1);
            }
        }

        let _ = write!(stdout, "{PROMPT}");
        let _ = stdout.flush();
    }
}
