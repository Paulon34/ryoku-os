{
  config,
  lib,
  pkgs,
  ...
}:

# Mutable build stamp for ryoku-doctor. MUST NOT use xdg.configFile / home.file
# for build-info.json — those become immutable /nix/store symlinks and conflict
# with activation writes (linkGeneration). State path only:
#   ~/.local/state/ryoku/build-info.json
let
  cfg = config.ryoku.profile;
  stateDir = "${config.home.homeDirectory}/.local/state/ryoku";
  # Approved checkout baked by host settingsApply.repoPath (never guessed here).
  approvedRepo = config.ryoku.settingsApply.repoPath;
in
{
  home.activation.ryokuBuildInfoStamp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state="${stateDir}"
    info="$state/build-info.json"
    mkdir -p "$state"

    date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo activation)

    # Only the host-approved checkout (settingsApply.repoPath). No ~/ryoku-os guessing.
    repo=${lib.escapeShellArg approvedRepo}
    commit=unknown
    if [ -n "$repo" ] && [ -d "$repo/distro/flake" ] && { [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; }; then
      if command -v git >/dev/null 2>&1; then
        commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)
      fi
    fi

    gen=active
    profile="/nix/var/nix/profiles/per-user/${config.home.username}/home-manager"
    if [ -L "$profile" ]; then
      target=$(readlink "$profile" || true)
      case "$target" in
        *home-manager-*-link*)
          gen=$(printf '%s' "$target" | sed -n 's/.*home-manager-\([0-9][0-9]*\)-link.*/\1/p')
          [ -n "$gen" ] || gen=active
          ;;
      esac
    fi

    # Escape repo for JSON string (no jq required).
    repo_json=$(printf '%s' "$repo" | ${pkgs.python3}/bin/python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

    # Write a regular file under XDG state (never a HM-managed symlink).
    cat >"$info" <<EOF
{
  "schemaVersion": 1,
  "ryokuVersion": "0.1.0-debian-desktop",
  "gitCommit": "$commit",
  "profile": "${cfg.edition}",
  "visual": "${cfg.visual}",
  "shellStyle": "${cfg.shellStyle}",
  "compositor": "${cfg.compositor}",
  "jarvis": ${if cfg.jarvis then "true" else "false"},
  "hmGeneration": "$gen",
  "buildDate": "$date_utc",
  "flake": "distro/flake",
  "repoPath": $repo_json
}
EOF
  '';

  home.packages = [
    (pkgs.writeShellScriptBin "ryoku-doctor" ''
      exec ${../../scripts/ryoku-doctor} "$@"
    '')
  ];
}
