{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  jq,
  ffmpeg,
  mpvpaper,
  systemd,
  matugen ? null,
}:

# Nix wrapper around distro/scripts/ryoku-video-wallpaper (Debian Modular).
# Runtime inputs stay on PATH for the packaged CLI; the script itself is the
# source of truth checked into git (same contract as ryoku-import-wallpaper).
writeShellApplication {
  name = "ryoku-video-wallpaper";

  runtimeInputs = [
    coreutils
    gawk
    jq
    ffmpeg
    mpvpaper
    systemd
  ]
  ++ lib.optional (matugen != null) matugen;

  # Script is the git source of truth; drop its shebang (wrapper provides one).
  text = lib.removePrefix "#!/usr/bin/env bash\n" (
    builtins.readFile ../../scripts/ryoku-video-wallpaper
  );

  meta = {
    description = "Ryoku video wallpaper runtime (mpvpaper + DMS poster/palette)";
    platforms = lib.platforms.linux;
    mainProgram = "ryoku-video-wallpaper";
  };
}
