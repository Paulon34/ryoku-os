{
  lib,
  stdenv,
  cmake,
  nix,
  home-manager,
  repoPath,
  flakeHost,
  flakeDir,
}:

assert builtins.isString repoPath && repoPath != "";
assert builtins.substring 0 1 repoPath == "/";
assert builtins.isString flakeDir && flakeDir != "";
assert builtins.substring 0 1 flakeDir == "/";

stdenv.mkDerivation {
  pname = "ryoku-settings-apply";
  version = "0.1.0-debian";

  src = ../../apps/ryoku-settings-apply;

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DRYOKU_REPO_PATH=${repoPath}"
    "-DRYOKU_FLAKE_HOST=${flakeHost}"
    "-DRYOKU_FLAKE_DIR=${flakeDir}"
    "-DRYOKU_HOME_MANAGER=${lib.getExe home-manager}"
    "-DRYOKU_NIX_ENV=${lib.getExe' nix "nix-env"}"
    "-DRYOKU_NIX=${lib.getExe' nix "nix"}"
    "-DRYOKU_RUNUSER=/usr/sbin/runuser"
    "-DRYOKU_DBUS_RUN_SESSION=/usr/bin/dbus-run-session"
  ];

  meta = {
    description = "Privileged Ryoku Settings apply/rollback helper (Debian Modular / Home Manager + Polkit)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ryoku-settings-apply";
  };
}
