{
  config,
  lib,
  pkgs,
  ...
}:

# Emit ~/.config/ryoku/build-info.json so ryoku-doctor can detect stale HM
# generations vs the git tip. Keep flake eval pure — git commit is filled at
# activation time from the checkout when available.
let
  cfg = config.ryoku.profile;

  payload = {
    schemaVersion = 1;
    ryokuVersion = "0.1.0-debian-desktop";
    gitCommit = "unknown";
    profile = cfg.edition;
    visual = cfg.visual;
    shellStyle = cfg.shellStyle;
    compositor = cfg.compositor;
    jarvis = cfg.jarvis;
    hmGeneration = "active";
    buildDate = "activation";
    flake = "distro/flake";
  };
in
{
  xdg.configFile."ryoku/build-info.json".text = builtins.toJSON payload + "\n";

  home.activation.ryokuBuildInfoStamp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    info="${config.home.homeDirectory}/.config/ryoku/build-info.json"
    mkdir -p "$(dirname "$info")"
    # Stamp date
    date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo activation)

    # Prefer RYOKU_REPO_PATH, then common checkout names.
    repo=""
    for cand in \
      "''${RYOKU_REPO_PATH:-}" \
      "${config.home.homeDirectory}/ryoku-os" \
      "${config.home.homeDirectory}/ryoku-os-visual" \
      "${config.home.homeDirectory}/ryoku"
    do
      if [ -n "$cand" ] && [ -d "$cand/distro/flake" ] && [ -d "$cand/.git" -o -f "$cand/.git" ]; then
        repo="$cand"
        break
      fi
    done

    commit=unknown
    if [ -n "$repo" ] && command -v git >/dev/null 2>&1; then
      commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)
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
  "flake": "distro/flake"
}
EOF
  '';

  home.packages = [
    (pkgs.writeShellScriptBin "ryoku-doctor" ''
      exec ${../../scripts/ryoku-doctor} "$@"
    '')
  ];
}
