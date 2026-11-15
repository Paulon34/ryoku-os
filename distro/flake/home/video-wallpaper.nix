{
  config,
  pkgs,
  lib,
  ...
}:

# Video wallpaper renderer (mpvpaper) for Ryoku Settings on Debian Modular.
#
# Static unit; selection is runtime state written by
# `ryoku-video-wallpaper apply` to ~/.local/state/ryoku/video-wallpaper.env
# (same live model as static wallpapers via DMS IPC — no rebuild per change).
# Without that file the unit does not start.
#
# Debian GDM → Hyprland may not reach graphical-session.target, so we also:
#   - WantedBy default.target via a path unit on the env file
#   - restart from ryoku-start-dms after DMS is up (see dms.nix)

let
  videoWallpaper = pkgs.callPackage ../pkgs/ryoku-video-wallpaper.nix {
    inherit (pkgs) matugen;
  };
  helper = lib.getExe videoWallpaper;
in
{
  home.packages = [ videoWallpaper ];

  # Stable PATH entry for Settings / gallery when HM profile PATH is trimmed.
  home.file.".local/bin/ryoku-video-wallpaper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      exec ${helper} "$@"
    '';
  };

  systemd.user.services.ryoku-video-wallpaper = {
    Unit = {
      Description = "Ryoku video wallpaper (mpvpaper)";
      # Prefer graphical-session when present; do not hard-require it (GDM).
      After = [
        "default.target"
        "graphical-session.target"
      ];
      ConditionPathExists = "%S/ryoku/video-wallpaper.env";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };

    Service = {
      Type = "simple";
      EnvironmentFile = "%S/ryoku/video-wallpaper.env";
      ExecCondition = "${helper} check";
      ExecStart = "${helper} run";
      ExecStartPost = [
        "${pkgs.coreutils}/bin/sleep 1.5"
        "${helper} dms-hide"
      ];
      ExecStopPost = "${helper} dms-restore";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 5;
    };

    # Path unit is the reliable Debian autostart; this WantedBy is best-effort.
    Install.WantedBy = [ "default.target" ];
  };

  # GDM/Hyprland: start when the env file appears (apply) or already exists
  # at login, without depending on graphical-session.target.
  systemd.user.paths.ryoku-video-wallpaper = {
    Unit.Description = "Watch Ryoku video wallpaper env for mpvpaper";
    Path = {
      PathExists = "%S/ryoku/video-wallpaper.env";
      Unit = "ryoku-video-wallpaper.service";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
