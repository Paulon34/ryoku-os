//! Ryoku console — limited interactive builtins (Mission 011).
//!
//! Separate from `ryoku-init` PID 1. Emitting boot-seed markers remains sole
//! responsibility of `ryoku-init`. This crate must not print
//! `RYOKU_BOOT_SEED_READY` or claim a product OS shell.

#![forbid(unsafe_code)]

use std::fmt;

/// Console process identity (not PID 1 init).
pub const CONSOLE_IDENTITY: &str = "ryoku-console";

/// Prompt shown by the host/guest REPL (prep).
pub const PROMPT: &str = "ryoku> ";

/// Hard caps — fail closed on oversized input.
pub const MAX_LINE_BYTES: usize = 256;
pub const MAX_ARG_BYTES: usize = 128;
pub const MAX_ARGS: usize = 16;

/// Builtins supported in Mission 011.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Help,
    Version,
    Status,
    Echo(Vec<String>),
    Clear,
}

/// Parse / validation failures (no shell fallback).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseError {
    Empty,
    TooLong { len: usize },
    ForbiddenChar { ch: char },
    ArgTooLong { index: usize, len: usize },
    TooManyArgs { count: usize },
    UnknownCommand { name: String },
    NonAscii,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => write!(f, "empty input"),
            Self::TooLong { len } => {
                write!(f, "line too long ({len} > {MAX_LINE_BYTES})")
            }
            Self::ForbiddenChar { ch } => {
                write!(f, "forbidden character U+{:04X} ({ch:?})", *ch as u32)
            }
            Self::ArgTooLong { index, len } => {
                write!(f, "argument {index} too long ({len} > {MAX_ARG_BYTES})")
            }
            Self::TooManyArgs { count } => {
                write!(f, "too many arguments ({count} > {MAX_ARGS})")
            }
            Self::UnknownCommand { name } => write!(f, "unknown command `{name}`"),
            Self::NonAscii => write!(f, "non-ASCII input rejected"),
        }
    }
}

impl std::error::Error for ParseError {}

/// Horizontal whitespace treated as token separators (not forbidden).
#[must_use]
pub fn is_horizontal_whitespace(ch: char) -> bool {
    matches!(ch, ' ' | '\t' | '\r')
}

/// Characters that must never appear (shell / expansion surface).
/// Tabs/CR are whitespace (see [`is_horizontal_whitespace`]), not forbidden.
#[must_use]
pub fn is_forbidden_char(ch: char) -> bool {
    matches!(
        ch,
        '|' | '&'
            | ';'
            | '`'
            | '$'
            | '>'
            | '<'
            | '('
            | ')'
            | '{'
            | '}'
            | '['
            | ']'
            | '*'
            | '?'
            | '~'
            | '\\'
            | '\''
            | '"'
            | '\0'
            | '\n'
    )
}

fn trim_horizontal(s: &str) -> &str {
    s.trim_matches(|c: char| is_horizontal_whitespace(c))
}

/// Split a line into tokens on horizontal whitespace (no quote state machine).
fn tokenize(line: &str) -> Result<Vec<String>, ParseError> {
    let mut tokens = Vec::new();
    let mut cur = String::new();
    for ch in line.chars() {
        if is_horizontal_whitespace(ch) {
            if !cur.is_empty() {
                if cur.len() > MAX_ARG_BYTES {
                    return Err(ParseError::ArgTooLong {
                        index: tokens.len(),
                        len: cur.len(),
                    });
                }
                tokens.push(std::mem::take(&mut cur));
            }
            continue;
        }
        if !ch.is_ascii() {
            return Err(ParseError::NonAscii);
        }
        if is_forbidden_char(ch) {
            return Err(ParseError::ForbiddenChar { ch });
        }
        // Allow a tight printable set: letters, digits, and a few safe punctuations.
        if !(ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.' | ':' | '/' | '=' | '+')) {
            return Err(ParseError::ForbiddenChar { ch });
        }
        cur.push(ch);
        if cur.len() > MAX_ARG_BYTES {
            return Err(ParseError::ArgTooLong {
                index: tokens.len(),
                len: cur.len(),
            });
        }
    }
    if !cur.is_empty() {
        if cur.len() > MAX_ARG_BYTES {
            return Err(ParseError::ArgTooLong {
                index: tokens.len(),
                len: cur.len(),
            });
        }
        tokens.push(cur);
    }
    if tokens.len() > MAX_ARGS {
        return Err(ParseError::TooManyArgs {
            count: tokens.len(),
        });
    }
    Ok(tokens)
}

/// Parse one console line into a [`Command`].
/// Leading/trailing spaces, tabs, and CR are ignored; internal ones separate tokens.
pub fn parse_line(raw: &str) -> Result<Command, ParseError> {
    // Enforce length on the raw input (before trim) so padded junk cannot bypass caps.
    if raw.len() > MAX_LINE_BYTES {
        return Err(ParseError::TooLong { len: raw.len() });
    }
    let line = trim_horizontal(raw);
    if line.is_empty() {
        return Err(ParseError::Empty);
    }
    if !line.is_ascii() {
        return Err(ParseError::NonAscii);
    }
    for ch in line.chars() {
        if is_horizontal_whitespace(ch) {
            continue;
        }
        if is_forbidden_char(ch) {
            return Err(ParseError::ForbiddenChar { ch });
        }
    }

    let tokens = tokenize(line)?;
    let Some(cmd) = tokens.first() else {
        return Err(ParseError::Empty);
    };

    match cmd.as_str() {
        "help" => {
            if tokens.len() != 1 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Help)
        }
        "version" => {
            if tokens.len() != 1 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Version)
        }
        "status" => {
            if tokens.len() != 1 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Status)
        }
        "clear" => {
            if tokens.len() != 1 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Clear)
        }
        "echo" => Ok(Command::Echo(tokens[1..].to_vec())),
        other => Err(ParseError::UnknownCommand {
            name: other.to_string(),
        }),
    }
}

/// Startup banner for the host REPL — must never contain boot-seed marker text.
#[must_use]
pub fn startup_banner(version: &str) -> String {
    format!(
        "{CONSOLE_IDENTITY} {version} — limited builtins; not a product OS shell\n\
         Separate from ryoku-init PID 1. Type `help`.\n"
    )
}

/// Render command output (no side effects beyond the returned string).
#[must_use]
pub fn render(cmd: &Command) -> String {
    match cmd {
        Command::Help => {
            "ryoku-console builtins:\n  help     — this list\n  version  — console version\n  status   — short honesty / readiness status\n  echo …   — print arguments (no expansion)\n  clear    — clear screen (ANSI)\n\nLimited parser: no shell metacharacters, no pipes/redirects/substitution.\nNot a product OS login shell. Separate from ryoku-init PID 1.\n"
                .to_string()
        }
        Command::Version => {
            format!("{CONSOLE_IDENTITY} {}\n", env!("CARGO_PKG_VERSION"))
        }
        Command::Status => {
            format!(
                "{CONSOLE_IDENTITY}: interactive prototype (Mission 011)\n\
                 pid1_core: separate (ryoku-init owns guest pid=1 markers)\n\
                 product_os_boot: NOT claimed\n\
                 parser: limited builtins only\n\
                 network: none (lab default)\n"
            )
        }
        Command::Echo(args) => {
            if args.is_empty() {
                "\n".to_string()
            } else {
                format!("{}\n", args.join(" "))
            }
        }
        Command::Clear => "\u{001b}[2J\u{001b}[H".to_string(),
    }
}

/// Parse then render; empty lines yield empty Ok for REPL convenience.
pub fn eval_line(raw: &str) -> Result<String, ParseError> {
    match parse_line(raw) {
        Err(ParseError::Empty) => Ok(String::new()),
        Err(err) => Err(err),
        Ok(cmd) => Ok(render(&cmd)),
    }
}

/// True when text contains the Boot Seed marker (must stay false for console-owned output).
#[must_use]
pub fn output_claims_boot_seed_ready(text: &str) -> bool {
    text.contains("RYOKU_BOOT_SEED_READY")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_version_status_clear_echo() {
        assert!(matches!(parse_line("help").unwrap(), Command::Help));
        assert!(matches!(parse_line("version").unwrap(), Command::Version));
        assert!(matches!(parse_line("status").unwrap(), Command::Status));
        assert!(matches!(parse_line("clear").unwrap(), Command::Clear));
        assert_eq!(
            parse_line("echo hello world").unwrap(),
            Command::Echo(vec!["hello".into(), "world".into()])
        );
        assert_eq!(
            render(&Command::Echo(vec!["a".into(), "b".into()])),
            "a b\n"
        );
        assert!(render(&Command::Clear).contains("\u{001b}[2J"));
        assert!(render(&Command::Version).starts_with("ryoku-console "));
    }

    #[test]
    fn accepts_tabs_and_cr_as_whitespace() {
        assert!(matches!(parse_line("\thelp\t").unwrap(), Command::Help));
        assert!(matches!(
            parse_line("\rversion\r").unwrap(),
            Command::Version
        ));
        assert_eq!(
            parse_line("echo\thello\tworld").unwrap(),
            Command::Echo(vec!["hello".into(), "world".into()])
        );
        assert_eq!(
            parse_line("echo\rhello\rworld").unwrap(),
            Command::Echo(vec!["hello".into(), "world".into()])
        );
    }

    #[test]
    fn rejects_shell_metacharacters() {
        for line in [
            "echo a|b",
            "echo a;b",
            "echo $(id)",
            "echo `id`",
            "echo a&&b",
            "echo >out",
            "echo <in",
            "echo $HOME",
            "echo 'x'",
            "echo \"x\"",
            "echo a\\b",
        ] {
            let err = parse_line(line).unwrap_err();
            assert!(
                matches!(err, ParseError::ForbiddenChar { .. }),
                "expected ForbiddenChar for {line:?}, got {err:?}"
            );
        }
    }

    #[test]
    fn rejects_unknown_and_oversized() {
        assert!(matches!(
            parse_line("rm -rf /").unwrap_err(),
            ParseError::UnknownCommand { .. }
        ));
        assert!(matches!(
            parse_line("sudo reboot").unwrap_err(),
            ParseError::UnknownCommand { .. }
        ));
        let long = "a".repeat(MAX_LINE_BYTES + 1);
        assert!(matches!(
            parse_line(&long).unwrap_err(),
            ParseError::TooLong { .. }
        ));
        // Whitespace padding must not hide oversize raw input.
        let padded = format!("  {}  ", "a".repeat(MAX_LINE_BYTES));
        assert!(padded.len() > MAX_LINE_BYTES);
        assert!(matches!(
            parse_line(&padded).unwrap_err(),
            ParseError::TooLong { .. }
        ));
        let many = format!("echo {}", vec!["x"; MAX_ARGS].join(" "));
        assert!(matches!(
            parse_line(&many).unwrap_err(),
            ParseError::TooManyArgs { .. }
        ));
    }

    #[test]
    fn console_owned_output_never_emits_boot_seed_ready() {
        let banner = startup_banner(env!("CARGO_PKG_VERSION"));
        assert!(!output_claims_boot_seed_ready(&banner));
        assert!(!banner.contains("READY"));
        for cmd in [
            Command::Help,
            Command::Version,
            Command::Status,
            Command::Clear,
        ] {
            let out = render(&cmd);
            assert!(!output_claims_boot_seed_ready(&out));
            assert!(
                !out.contains("READY"),
                "console-owned output must not contain READY: {out:?}"
            );
        }
        // Echo may print a literal user token — that is not a console claim.
        assert!(!output_claims_boot_seed_ready(&render(&Command::Help)));
    }

    #[test]
    fn eval_empty_ok() {
        assert_eq!(eval_line("   ").unwrap(), "");
        assert_eq!(eval_line("\t\t").unwrap(), "");
        assert_eq!(eval_line("\r").unwrap(), "");
    }
}
