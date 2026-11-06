//! External command execution behind a trait (testable).

use std::collections::HashMap;
use std::ffi::OsStr;
use std::io;
use std::process::Command;

/// Captured result of running a program (stdout/stderr already lossy-decoded).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandOutput {
    pub status_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    /// `None` means the OS could not spawn the process (e.g. not found).
    pub spawn_error: Option<String>,
}

impl CommandOutput {
    #[must_use]
    pub fn ok(stdout: impl Into<String>) -> Self {
        Self {
            status_code: Some(0),
            stdout: stdout.into(),
            stderr: String::new(),
            spawn_error: None,
        }
    }

    #[must_use]
    pub fn not_found(program: &str) -> Self {
        Self {
            status_code: None,
            stdout: String::new(),
            stderr: String::new(),
            spawn_error: Some(format!("failed to execute {program}: not found")),
        }
    }

    #[must_use]
    pub fn failed(code: i32, stderr: impl Into<String>) -> Self {
        Self {
            status_code: Some(code),
            stdout: String::new(),
            stderr: stderr.into(),
            spawn_error: None,
        }
    }

    #[must_use]
    pub fn success(&self) -> bool {
        self.spawn_error.is_none() && self.status_code == Some(0)
    }

    /// First non-empty line of stdout, trimmed — handy for `--version` banners.
    #[must_use]
    pub fn first_line(&self) -> Option<&str> {
        self.stdout
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
    }
}

/// Abstraction over `std::process::Command` for diagnostics.
pub trait CommandRunner {
    fn run(&self, program: &str, args: &[&str]) -> CommandOutput;
}

/// Real host runner — never elevates privileges; never installs packages.
#[derive(Debug, Default, Clone, Copy)]
pub struct HostCommandRunner;

impl CommandRunner for HostCommandRunner {
    fn run(&self, program: &str, args: &[&str]) -> CommandOutput {
        match Command::new(program)
            .args(args.iter().map(OsStr::new))
            .output()
        {
            Ok(output) => CommandOutput {
                status_code: output.status.code(),
                stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
                stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
                spawn_error: None,
            },
            Err(err) => CommandOutput {
                status_code: None,
                stdout: String::new(),
                stderr: String::new(),
                spawn_error: Some(format_spawn_error(program, &err)),
            },
        }
    }
}

fn format_spawn_error(program: &str, err: &io::Error) -> String {
    if err.kind() == io::ErrorKind::NotFound {
        format!("failed to execute {program}: not found on PATH")
    } else {
        format!("failed to execute {program}: {err}")
    }
}

/// Map from (`program`, `args joined`) → canned [`CommandOutput`].
#[derive(Debug, Default, Clone)]
pub struct MockRunner {
    responses: HashMap<String, CommandOutput>,
    default_not_found: bool,
}

impl MockRunner {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn with_default_not_found(mut self) -> Self {
        self.default_not_found = true;
        self
    }

    pub fn insert(&mut self, program: &str, args: &[&str], output: CommandOutput) {
        self.responses.insert(key(program, args), output);
    }

    #[must_use]
    pub fn with(mut self, program: &str, args: &[&str], output: CommandOutput) -> Self {
        self.insert(program, args, output);
        self
    }
}

fn key(program: &str, args: &[&str]) -> String {
    let mut k = program.to_string();
    for arg in args {
        k.push('\0');
        k.push_str(arg);
    }
    k
}

impl CommandRunner for MockRunner {
    fn run(&self, program: &str, args: &[&str]) -> CommandOutput {
        if let Some(output) = self.responses.get(&key(program, args)) {
            return output.clone();
        }
        if self.default_not_found {
            return CommandOutput::not_found(program);
        }
        CommandOutput {
            status_code: None,
            stdout: String::new(),
            stderr: String::new(),
            spawn_error: Some(format!(
                "mock runner has no response for `{program} {}`",
                args.join(" ")
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mock_returns_configured_output() {
        let runner =
            MockRunner::new().with("rustc", &["--version"], CommandOutput::ok("rustc 1.83.0\n"));
        let out = runner.run("rustc", &["--version"]);
        assert!(out.success());
        assert_eq!(out.first_line(), Some("rustc 1.83.0"));
    }

    #[test]
    fn mock_default_not_found() {
        let runner = MockRunner::new().with_default_not_found();
        let out = runner.run("qemu-system-x86_64", &["--version"]);
        assert!(!out.success());
        assert!(out.spawn_error.as_ref().unwrap().contains("not found"));
    }

    #[test]
    fn command_output_helpers() {
        assert!(CommandOutput::ok("x").success());
        assert!(!CommandOutput::failed(1, "boom").success());
        assert!(!CommandOutput::not_found("x").success());
    }
}
