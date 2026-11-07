//! REPL for `ryoku-console` (host prep + guest Minimal child).
//!
//! Not PID 1. Exit cleanly on EOF (Ctrl-D). Guest stdin/stdout are usually
//! `/dev/console` (wired by `ryoku-init`). Line I/O uses capped
//! [`ryoku_console::read_limited_line`] (fill_buf/consume).

#![forbid(unsafe_code)]

use std::env;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use ryoku_console::{
    eval_line_in, read_limited_line, startup_banner, LimitedLine, ParseError, Session, PROMPT,
};

fn session_from_env() -> Session {
    if let Ok(root) = env::var("RYOKU_CONSOLE_ROOT") {
        return Session::with_root(PathBuf::from(root));
    }
    // Guest Minimal: experimental FS is the initramfs root.
    Session::guest_default()
}

fn main() -> ExitCode {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut input = stdin.lock();
    let session = session_from_env();

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
            Ok(LimitedLine::InvalidBytes) => {
                let _ = writeln!(stdout, "error: {}", ParseError::NonAscii);
            }
            Ok(LimitedLine::Line(line)) => match eval_line_in(&session, &line) {
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
