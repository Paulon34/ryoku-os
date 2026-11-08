# Home Manager hosts

Each directory `hosts/<name>/default.nix` becomes `homeConfigurations.<name>`.

Bootstrap writes (and `git add`s) `hosts/<user>/default.nix` with the real
`username`, `homeDirectory`, and profile knobs. **Do not** use a gitignored
overlay — flakes ignore untracked/gitignored files in pure evaluation.

```nix
{
  username = "alice";
  homeDirectory = "/home/alice";
  profile = {
    edition = "minimal";
    visual = "balanced";
    shellStyle = "quattro";
    jarvis = false;
  };
}
```

Then:

```bash
home-manager switch --flake ./distro/flake#alice
```

Committed references:

- `hosts/ryoku` — Quattro default (`shellStyle = "quattro"`)
- `hosts/ryoku-islands` — Islands visual test (`shellStyle = "islands"`)

```bash
home-manager switch --flake ./distro/flake#ryoku-islands
```
