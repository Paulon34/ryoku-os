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
# GDM → Hyprland often never reaches graphical-session.target. Autostart is:
#   - path unit WantedBy=default.target (watches the env file)
#   - explicit start from ryoku-start-dms after DMS is up
# The service itself must NOT WantedBy+After default.target (dependency cycle).

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
      # Ordering hint only when a graphical session exists — never After=default.target
      # (that cycles with path/service WantedBy=default.target under user systemd).
      After = [ "graphical-session.target" ];
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
      # Stop orphans even when the main PID already died.
      ExecStop = "${helper} stop-orphans";
      ExecStopPost = "${helper} dms-restore";
      KillMode = "control-group";
      KillSignal = "SIGTERM";
      TimeoutStopSec = 8;
      Restart = "on-failure";
      RestartSec = 5;
      # After StartLimitBurst, stay failed; DMS static wallpaper remains via ExecStopPost.
      RemainAfterExit = false;
    };

    # Not installed into a target — the path unit (and ryoku-start-dms) start it.
  };

  # Start when the env file appears (apply) or already exists at login.
  systemd.user.paths.ryoku-video-wallpaper = {
    Unit.Description = "Watch Ryoku video wallpaper env for mpvpaper";
    Path = {
      PathExists = "%S/ryoku/video-wallpaper.env";
      Unit = "ryoku-video-wallpaper.service";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
