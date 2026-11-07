//! Ryoku console — limited interactive builtins (Mission 011 / 012).
//!
//! Separate from `ryoku-init` PID 1. Emitting boot-seed markers remains sole
//! responsibility of `ryoku-init`. This crate must not print
//! `RYOKU_BOOT_SEED_READY` or claim a product OS shell.
//!
//! Mission 012 adds experimental FS builtins (`pwd` / `ls` / `cat`) confined to
//! a staged root — still not an external shell.

#![forbid(unsafe_code)]

pub mod fs;

use std::fmt;
use std::io::{self, BufRead};
use std::path::PathBuf;

pub use fs::{FsError, GuestFs, MAX_CAT_BYTES};

/// Console process identity (not PID 1 init).
pub const CONSOLE_IDENTITY: &str = "ryoku-console";

/// Prompt shown by the host/guest REPL (prep).
pub const PROMPT: &str = "ryoku> ";

/// Hard caps — fail closed on oversized input.
pub const MAX_LINE_BYTES: usize = 256;
pub const MAX_ARG_BYTES: usize = 128;
pub const MAX_ARGS: usize = 16;

/// Extra bytes the limited reader may scan past [`MAX_LINE_BYTES`] while looking
/// for a CRLF/LF terminator before declaring the line too long.
pub const LINE_READ_MARGIN: usize = 2;

/// Builtins supported in Mission 011 + experimental FS (Mission 012).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Help,
    Version,
    Status,
    Echo(Vec<String>),
    Clear,
    Pwd,
    Ls(Option<String>),
    Cat(String),
}

/// REPL session holding an optional confined FS cursor.
///
/// Host without `RYOKU_CONSOLE_ROOT` → [`Session::without_fs`] (`pwd`/`ls`/`cat`
/// refuse). Guest Minimal gets `RYOKU_CONSOLE_ROOT=/` from `ryoku-init`.
#[derive(Debug, Clone)]
pub struct Session {
    pub fs: Option<GuestFs>,
}

impl Session {
    #[must_use]
    pub fn new(fs: GuestFs) -> Self {
        Self { fs: Some(fs) }
    }

    /// Host REPL without experimental FS (help/version/status/echo/clear only).
    #[must_use]
    pub fn without_fs() -> Self {
        Self { fs: None }
    }

    /// Guest default: root `/`, cwd `/home/ryoku` when present.
    #[must_use]
    pub fn guest_default() -> Self {
        Self::new(GuestFs::guest_root())
    }

    /// Host/test session rooted at `root` (validates: plain dir, not symlink).
    pub fn with_root(root: PathBuf) -> Result<Self, FsError> {
        Ok(Self::new(GuestFs::validated_root(root)?))
    }
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

/// Outcome of one capped line read from a [`BufRead`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LimitedLine {
    /// Payload without LF / CRLF terminator.
    Line(String),
    /// Line exceeded [`MAX_LINE_BYTES`] (reader drained through the terminator).
    TooLong { observed: usize },
    /// Non-UTF-8 bytes in the line payload (reader drained through the terminator when present).
    InvalidBytes,
    /// No more input.
    Eof,
}

/// Characters that must never appear in a command payload.
/// Tabs and CR are **rejected** in commands; CRLF is stripped only by the I/O reader.
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
            | '\r'
            | '\t'
    )
}

/// Split a line into tokens on ASCII spaces only (no quote state machine).
fn tokenize(line: &str) -> Result<Vec<String>, ParseError> {
    let mut tokens = Vec::new();
    let mut cur = String::new();
    for ch in line.chars() {
        if ch == ' ' {
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
///
/// Only ASCII spaces (`' '`) are allowed as leading/trailing padding and token
/// separators. Do **not** use [`str::trim`]: it would silently strip tabs/CR and
/// other Unicode whitespace that must remain visible to validation.
pub fn parse_line(raw: &str) -> Result<Command, ParseError> {
    if raw.len() > MAX_LINE_BYTES {
        return Err(ParseError::TooLong { len: raw.len() });
    }
    // Space-only edges — never `trim()` / Unicode whitespace classes.
    let line = raw.trim_matches(' ');
    if line.is_empty() {
        return Err(ParseError::Empty);
    }
    if !line.is_ascii() {
        return Err(ParseError::NonAscii);
    }
    for ch in line.chars() {
        if ch == ' ' {
            continue;
        }
        if is_forbidden_char(ch) {
            return Err(ParseError::ForbiddenChar { ch });
        }
        // Catch remaining C0 controls (and DEL) before tokenize.
        if ch.is_ascii_control() {
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
        "pwd" => {
            if tokens.len() != 1 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Pwd)
        }
        "ls" => {
            if tokens.len() > 2 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Ls(tokens.get(1).cloned()))
        }
        "cat" => {
            if tokens.len() != 2 {
                return Err(ParseError::TooManyArgs {
                    count: tokens.len(),
                });
            }
            Ok(Command::Cat(tokens[1].clone()))
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

/// Render pure (non-FS) command output.
#[must_use]
pub fn render(cmd: &Command) -> String {
    match cmd {
        Command::Help => {
            "ryoku-console builtins:\n  help     — this list\n  version  — console version\n  status   — short honesty / readiness status\n  echo …   — print arguments (no expansion)\n  clear    — clear screen (ANSI)\n  pwd      — print experimental cwd\n  ls [path]— list directory (experimental FS)\n  cat path — read file (experimental FS, capped)\n\nLimited parser: no shell metacharacters, no pipes/redirects/substitution.\nNot a product OS login shell. Separate from ryoku-init PID 1.\n"
                .to_string()
        }
        Command::Version => {
            format!("{CONSOLE_IDENTITY} {}\n", env!("CARGO_PKG_VERSION"))
        }
        Command::Status => {
            format!(
                "{CONSOLE_IDENTITY}: Ryoku Minimal interactive (Mission 012)\n\
                 pid1_core: separate (ryoku-init owns guest pid=1 markers)\n\
                 product_os_boot: NOT claimed\n\
                 parser: limited builtins only\n\
                 fs: experimental initramfs view (pwd/ls/cat)\n\
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
        // FS commands need a session — callers should use `eval_line_in`.
        Command::Pwd | Command::Ls(_) | Command::Cat(_) => {
            format!("{CONSOLE_IDENTITY}: internal: FS command requires session\n")
        }
    }
}

/// Eval FS-aware command against a [`Session`].
pub fn render_in(session: &Session, cmd: &Command) -> Result<String, FsError> {
    match cmd {
        Command::Pwd | Command::Ls(_) | Command::Cat(_) => {
            let Some(fs) = session.fs.as_ref() else {
                return Err(FsError::RootRequired);
            };
            match cmd {
                Command::Pwd => Ok(fs.pwd()),
                Command::Ls(path) => fs.ls(path.as_deref()),
                Command::Cat(path) => fs.cat(path),
                _ => unreachable!(),
            }
        }
        other => Ok(render(other)),
    }
}

/// Parse then render without FS (FS commands return a session-required message).
/// Empty lines yield empty Ok for REPL convenience.
pub fn eval_line(raw: &str) -> Result<String, ParseError> {
    match parse_line(raw) {
        Err(ParseError::Empty) => Ok(String::new()),
        Err(err) => Err(err),
        Ok(cmd) => Ok(render(&cmd)),
    }
}

/// Parse + session-aware eval. FS errors are mapped to a display string via `Err`.
pub fn eval_line_in(session: &Session, raw: &str) -> Result<String, String> {
    match parse_line(raw) {
        Err(ParseError::Empty) => Ok(String::new()),
        Err(err) => Err(err.to_string()),
        Ok(cmd) => render_in(session, &cmd).map_err(|e| e.to_string()),
    }
}

/// True when text contains the Boot Seed marker (must stay false for console-owned output).
#[must_use]
pub fn output_claims_boot_seed_ready(text: &str) -> bool {
    text.contains("RYOKU_BOOT_SEED_READY")
}

fn drain_until_lf<R: BufRead>(reader: &mut R) -> io::Result<()> {
    loop {
        let buf = reader.fill_buf()?;
        if buf.is_empty() {
            return Ok(());
        }
        if let Some(nl) = buf.iter().position(|&b| b == b'\n') {
            reader.consume(nl + 1);
            return Ok(());
        }
        let n = buf.len();
        reader.consume(n);
    }
}

/// Read one line via [`BufRead::fill_buf`] / [`BufRead::consume`] with a hard cap.
///
/// - Terminators: `\n` or `\r\n` only (CRLF stripped at the I/O boundary).
/// - CRLF may span two `fill_buf` results (`…\r` then `\n…`); mid-line `\r` stays in the payload.
/// - On overflow, discards through the LF **without** allocating a copy of the long line.
/// - Never accumulates more than [`MAX_LINE_BYTES`] + [`LINE_READ_MARGIN`] without a terminator.
pub fn read_limited_line<R: BufRead>(reader: &mut R) -> io::Result<LimitedLine> {
    let mut line: Vec<u8> = Vec::with_capacity(MAX_LINE_BYTES + LINE_READ_MARGIN);
    let hard_cap = MAX_LINE_BYTES + LINE_READ_MARGIN;

    loop {
        let buf = reader.fill_buf()?;
        if buf.is_empty() {
            if line.is_empty() {
                return Ok(LimitedLine::Eof);
            }
            // EOF without terminator — deliver what we have (parser may still reject).
            return match String::from_utf8(line) {
                Ok(s) => Ok(LimitedLine::Line(s)),
                Err(_) => Ok(LimitedLine::InvalidBytes),
            };
        }

        if let Some(nl) = buf.iter().position(|&b| b == b'\n') {
            // CRLF in-buffer, or CR held from a prior fill_buf then LF here.
            let (payload_end, drop_pending_cr) = if nl > 0 && buf[nl - 1] == b'\r' {
                (nl - 1, false)
            } else if nl == 0 && line.last() == Some(&b'\r') {
                (0, true)
            } else {
                (nl, false)
            };

            let mut observed = line.len() + payload_end;
            if drop_pending_cr {
                observed = observed.saturating_sub(1);
            }

            // Cap check before any allocate/copy of this chunk.
            if observed > MAX_LINE_BYTES {
                reader.consume(nl + 1);
                return Ok(LimitedLine::TooLong { observed });
            }

            if payload_end > 0 {
                line.extend_from_slice(&buf[..payload_end]);
            }
            reader.consume(nl + 1);
            if drop_pending_cr {
                let _ = line.pop();
            }
            return match String::from_utf8(line) {
                Ok(s) => Ok(LimitedLine::Line(s)),
                Err(_) => Ok(LimitedLine::InvalidBytes),
            };
        }

        // No LF — append under hard_cap without a temporary proportional to input length.
        if line.len() + buf.len() > hard_cap {
            let observed = line.len() + buf.len();
            let n = buf.len();
            reader.consume(n);
            drain_until_lf(reader)?;
            return Ok(LimitedLine::TooLong { observed });
        }

        let n = buf.len();
        line.extend_from_slice(buf);
        reader.consume(n);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufReader, Cursor};

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
    fn pwd_ls_cat_parse_and_session_eval() {
        assert!(matches!(parse_line("pwd").unwrap(), Command::Pwd));
        assert_eq!(parse_line("ls").unwrap(), Command::Ls(None));
        assert_eq!(
            parse_line("ls /etc").unwrap(),
            Command::Ls(Some("/etc".into()))
        );
        assert_eq!(
            parse_line("cat /etc/ryoku-release").unwrap(),
            Command::Cat("/etc/ryoku-release".into())
        );
        assert!(matches!(
            parse_line("cat").unwrap_err(),
            ParseError::TooManyArgs { count: 1 }
        ));

        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("ryoku-console-sess-{nanos}"));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("home/ryoku")).unwrap();
        std::fs::create_dir_all(root.join("etc")).unwrap();
        std::fs::write(root.join("etc/ryoku-release"), b"ryoku-minimal\n").unwrap();
        std::fs::write(root.join("home/ryoku/note.txt"), b"hi\n").unwrap();
        let session = Session::with_root(root.clone()).unwrap();
        assert_eq!(eval_line_in(&session, "pwd").unwrap(), "/home/ryoku\n");
        assert!(eval_line_in(&session, "ls").unwrap().contains("note.txt"));
        assert_eq!(
            eval_line_in(&session, "cat /etc/ryoku-release").unwrap(),
            "ryoku-minimal\n"
        );
        assert!(eval_line_in(&session, "cat /../../etc/passwd")
            .unwrap_err()
            .contains("escape"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn host_without_fs_root_keeps_non_fs_builtins() {
        let session = Session::without_fs();
        assert!(eval_line_in(&session, "help").unwrap().contains("help"));
        assert!(eval_line_in(&session, "version")
            .unwrap()
            .starts_with("ryoku-console "));
        assert!(eval_line_in(&session, "status")
            .unwrap()
            .contains("Mission"));
        assert_eq!(eval_line_in(&session, "echo hi").unwrap(), "hi\n");
        assert!(eval_line_in(&session, "clear")
            .unwrap()
            .contains("\u{001b}[2J"));
        for cmd in ["pwd", "ls", "ls /", "cat /etc/passwd"] {
            let err = eval_line_in(&session, cmd).unwrap_err();
            assert!(
                err.contains("RYOKU_CONSOLE_ROOT"),
                "expected RootRequired for {cmd}, got {err}"
            );
            assert!(!err.contains("EXTERNAL"));
        }
    }

    #[test]
    fn rejects_tabs_and_cr_inside_commands() {
        for line in ["\thelp", "help\t", "echo\thello", "echo hello\tworld"] {
            assert!(
                matches!(
                    parse_line(line).unwrap_err(),
                    ParseError::ForbiddenChar { ch: '\t' }
                ),
                "tab should be forbidden in {line:?}"
            );
        }
        for line in ["\rhelp", "help\r", "echo\rhello", "echo hello\rworld"] {
            assert!(
                matches!(
                    parse_line(line).unwrap_err(),
                    ParseError::ForbiddenChar { ch: '\r' }
                ),
                "CR should be forbidden in {line:?}"
            );
        }
    }

    #[test]
    fn rejects_unexpected_newlines_and_control_chars() {
        for line in ["help\n", "\nhelp", "echo hello\nworld", "help\nversion"] {
            assert!(
                matches!(
                    parse_line(line).unwrap_err(),
                    ParseError::ForbiddenChar { ch: '\n' }
                ),
                "embedded newline must fail for {line:?}"
            );
        }
        for (line, ch) in [
            ("help\u{0001}", '\u{0001}'),
            ("\u{0007}help", '\u{0007}'),
            ("echo\u{001b}hi", '\u{001b}'),
            ("status\u{007f}", '\u{007f}'),
            ("echo\0x", '\0'),
        ] {
            assert!(
                matches!(
                    parse_line(line).unwrap_err(),
                    ParseError::ForbiddenChar { ch: got } if got == ch
                ),
                "control {ch:?} must fail for {line:?}"
            );
        }
    }

    #[test]
    fn ascii_spaces_only_are_trimmed_not_tabs() {
        assert!(matches!(parse_line("  help  ").unwrap(), Command::Help));
        // `trim()` would hide the leading tab; space-only trim must not.
        assert!(matches!(
            parse_line("\thelp").unwrap_err(),
            ParseError::ForbiddenChar { ch: '\t' }
        ));
    }

    #[test]
    fn echo_may_reproduce_ready_text_without_console_claiming_boot() {
        let out = eval_line("echo RYOKU_BOOT_SEED_READY").unwrap();
        assert_eq!(out, "RYOKU_BOOT_SEED_READY\n");
        assert!(!output_claims_boot_seed_ready(&startup_banner("0.0.0")));
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
        let long = "a".repeat(MAX_LINE_BYTES + 1);
        assert!(matches!(
            parse_line(&long).unwrap_err(),
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
            Command::Pwd,
            Command::Ls(None),
            Command::Cat("x".into()),
        ] {
            let out = render(&cmd);
            assert!(!output_claims_boot_seed_ready(&out));
            assert!(!out.contains("READY"), "must not contain READY: {out:?}");
        }
    }

    #[test]
    fn repl_script_without_qemu_help_pwd() {
        // Future guest harness shape — host-side dialogue, no QEMU.
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("ryoku-console-repl-{nanos}"));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("home/ryoku")).unwrap();
        std::fs::create_dir_all(root.join("etc")).unwrap();
        std::fs::write(root.join("etc/ryoku-release"), b"ryoku-minimal 0.1.0\n").unwrap();
        let session = Session::with_root(root.clone()).unwrap();
        let script = ["help", "pwd", "ls /etc", "cat /etc/ryoku-release", "status"];
        let mut out = String::new();
        for line in script {
            out.push_str(&eval_line_in(&session, line).unwrap());
        }
        assert!(out.contains("pwd"));
        assert!(out.contains("/home/ryoku"));
        assert!(out.contains("ryoku-release"));
        assert!(out.contains("ryoku-minimal 0.1.0"));
        assert!(!output_claims_boot_seed_ready(&out));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn eval_empty_ok() {
        assert_eq!(eval_line("   ").unwrap(), "");
    }

    #[test]
    fn cursor_read_lf_and_crlf_terminators() {
        let mut cur = Cursor::new(b"help\nversion\r\nstatus\n");
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("help".into())
        );
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("version".into())
        );
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("status".into())
        );
        assert_eq!(read_limited_line(&mut cur).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_mid_line_cr_stays_for_parser_reject() {
        let mut cur = Cursor::new(b"echo hello\rworld\n");
        match read_limited_line(&mut cur).unwrap() {
            LimitedLine::Line(s) => {
                assert_eq!(s, "echo hello\rworld");
                assert!(matches!(
                    parse_line(&s).unwrap_err(),
                    ParseError::ForbiddenChar { ch: '\r' }
                ));
            }
            other => panic!("expected Line, got {other:?}"),
        }
    }

    #[test]
    fn cursor_read_too_long_drains_and_next_line_ok() {
        let mut payload = "a".repeat(MAX_LINE_BYTES + 10);
        payload.push_str("\nhelp\n");
        let mut cur = Cursor::new(payload.into_bytes());
        match read_limited_line(&mut cur).unwrap() {
            LimitedLine::TooLong { observed } => assert!(observed > MAX_LINE_BYTES),
            other => panic!("expected TooLong, got {other:?}"),
        }
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("help".into())
        );
        assert_eq!(read_limited_line(&mut cur).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_respects_cap_plus_margin() {
        // Exactly MAX bytes + LF is OK.
        let mut ok = "b".repeat(MAX_LINE_BYTES);
        ok.push('\n');
        let mut cur = Cursor::new(ok.into_bytes());
        match read_limited_line(&mut cur).unwrap() {
            LimitedLine::Line(s) => assert_eq!(s.len(), MAX_LINE_BYTES),
            other => panic!("expected Line, got {other:?}"),
        }

        // MAX+1 without early LF → TooLong (margin only for terminator scan).
        let mut over = "c".repeat(MAX_LINE_BYTES + LINE_READ_MARGIN + 1);
        over.push_str("\nclear\n");
        let mut cur = Cursor::new(over.into_bytes());
        assert!(matches!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::TooLong { .. }
        ));
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("clear".into())
        );
    }

    #[test]
    fn cursor_read_invalid_bytes_then_valid_command() {
        let mut cur = Cursor::new(b"hel\xffp\nversion\n");
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::InvalidBytes
        );
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("version".into())
        );
        assert_eq!(read_limited_line(&mut cur).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_eof_without_payload() {
        let mut cur = Cursor::new(b"");
        assert_eq!(read_limited_line(&mut cur).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_crlf_split_across_fill_buf_capacity_1() {
        let mut reader = BufReader::with_capacity(1, Cursor::new(b"help\r\nversion\n"));
        assert_eq!(
            read_limited_line(&mut reader).unwrap(),
            LimitedLine::Line("help".into())
        );
        assert_eq!(
            read_limited_line(&mut reader).unwrap(),
            LimitedLine::Line("version".into())
        );
        assert_eq!(read_limited_line(&mut reader).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_huge_line_lf_same_buffer_no_copy_before_cap() {
        // Oversized payload + LF in one Cursor buffer: TooLong without keeping the junk,
        // then the next command must still parse.
        let mut payload = "x".repeat(MAX_LINE_BYTES * 8);
        payload.push_str("\nstatus\n");
        let mut cur = Cursor::new(payload.into_bytes());
        match read_limited_line(&mut cur).unwrap() {
            LimitedLine::TooLong { observed } => {
                assert!(observed > MAX_LINE_BYTES);
                assert!(observed >= MAX_LINE_BYTES * 8);
            }
            other => panic!("expected TooLong, got {other:?}"),
        }
        assert_eq!(
            read_limited_line(&mut cur).unwrap(),
            LimitedLine::Line("status".into())
        );
        assert_eq!(read_limited_line(&mut cur).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_exact_256_byte_limit() {
        let mut exact = "e".repeat(MAX_LINE_BYTES);
        exact.push('\n');
        let mut cur = Cursor::new(exact.into_bytes());
        match read_limited_line(&mut cur).unwrap() {
            LimitedLine::Line(s) => {
                assert_eq!(s.len(), 256);
                assert_eq!(s.len(), MAX_LINE_BYTES);
            }
            other => panic!("expected Line at exact cap, got {other:?}"),
        }
        assert_eq!(read_limited_line(&mut cur).unwrap(), LimitedLine::Eof);
    }

    #[test]
    fn cursor_read_isolated_cr_mid_command_stays_forbidden() {
        let mut reader = BufReader::with_capacity(1, Cursor::new(b"echo\rhello\n"));
        match read_limited_line(&mut reader).unwrap() {
            LimitedLine::Line(s) => {
                assert_eq!(s, "echo\rhello");
                assert!(matches!(
                    parse_line(&s).unwrap_err(),
                    ParseError::ForbiddenChar { ch: '\r' }
                ));
            }
            other => panic!("expected Line with mid-command CR, got {other:?}"),
        }
    }
}
