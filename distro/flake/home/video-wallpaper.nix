{
  config,
  pkgs,
  lib,
  nixGL,
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
    nixGLIntel = nixGL.packages.${pkgs.stdenv.hostPlatform.system}.nixGLIntel;
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

  # Battery/AC tips for wallpaper economy + optional power-profiles-daemon.
  home.file.".local/bin/ryoku-power-policy" = {
    executable = true;
    source = ../../scripts/ryoku-power-policy;
  };

  # Optional oneshot on login (safe no-op when no battery / no video env).
  systemd.user.services.ryoku-power-policy = {
    Unit = {
      Description = "Ryoku smart power policy tips (battery/AC)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.homeDirectory}/.local/bin/ryoku-power-policy apply";
    };
  };

  systemd.user.timers.ryoku-power-policy = {
    Unit.Description = "Re-evaluate Ryoku power policy periodically";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = false;
      Unit = "ryoku-power-policy.service";
    };
    Install.WantedBy = [ "timers.target" ];
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

  # Smart pause/unload controller (Hyprland IPC when available).
  # Separated from the renderer so stopping mpvpaper does not kill the watcher.
  # No After=default.target; started by apply / path / ryoku-start-dms.
  systemd.user.services.ryoku-video-wallpaper-smart = {
    Unit = {
      Description = "Ryoku video wallpaper smart pause/unload";
      After = [ "ryoku-video-wallpaper.service" ];
      ConditionPathExists = "%S/ryoku/video-wallpaper.env";
    };
    Service = {
      Type = "simple";
      EnvironmentFile = "%S/ryoku/video-wallpaper.env";
      ExecStart = "${helper} watch";
      Restart = "on-failure";
      RestartSec = 8;
    };
  };

  systemd.user.paths.ryoku-video-wallpaper-smart = {
    Unit.Description = "Start smart wallpaper controller when env exists";
    Path = {
      PathExists = "%S/ryoku/video-wallpaper.env";
      Unit = "ryoku-video-wallpaper-smart.service";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
