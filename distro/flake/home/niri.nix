{ config, pkgs, lib, ... }:

# Niri recovery compositor (Debian Modular). Active only when
# ryoku.profile.compositor = "niri". Helpers live in session-helpers.nix.
# Matrix: docs/migration/HYPRLAND_TO_NIRI_KEYBINDS.md
let
  enabled = config.ryoku.profile.compositor == "niri";
  islands = config.ryoku.profile.shellStyle == "islands";
  gaps = if islands then 10 else 8;

  conf = ''
    // Ryoku Niri — recovery session (shellStyle-aware)
    // colors.kdl = HM/user-matugen fallback; dms/colors.kdl = DMS Material You
    include optional=true "colors.kdl"
    include optional=true "dms/colors.kdl"

    input {
        keyboard {
            xkb {
            }
            numlock
        }
        touchpad {
            tap
            natural-scroll
        }
    }

    layout {
        gaps ${toString gaps}
        center-focused-column "never"
        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }
        default-column-width { proportion 0.5; }
        focus-ring {
            width 2
            active-color "#8a9099"
            inactive-color "#3a3a3a"
        }
    }

    spawn-at-startup "${config.home.homeDirectory}/.local/bin/ryoku-nm-applet"
    spawn-at-startup "${config.home.homeDirectory}/.local/bin/ryoku-polkit-agent"
    spawn-at-startup "${config.home.homeDirectory}/.local/bin/ryoku-cliphist-text"
    spawn-at-startup "${config.home.homeDirectory}/.local/bin/ryoku-cliphist-image"
    spawn-at-startup "${config.home.homeDirectory}/.local/bin/ryoku-start-dms"

    prefer-no-csd

    screenshot-path "~/Pictures/Screenshots/ryoku-%Y%m%d-%H%M%S.png"

    hotkey-overlay {
        skip-at-startup
    }

    binds {
        Mod+Return { spawn "${pkgs.kitty}/bin/kitty"; }
        Mod+Space { spawn "${config.home.homeDirectory}/.local/bin/ryoku-launcher"; }
        Mod+E { spawn "thunar"; }

        Mod+Q { close-window; }
        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }

        Mod+Left  { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up    { focus-window-up; }
        Mod+Down  { focus-window-down; }
        Mod+H { focus-column-left; }
        Mod+L { focus-column-right; }
        Mod+K { focus-window-up; }
        Mod+J { focus-window-down; }

        Mod+Shift+H { move-column-left; }
        Mod+Shift+L { move-column-right; }
        Mod+Shift+K { move-window-up; }
        Mod+Shift+J { move-window-down; }

        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+6 { focus-workspace 6; }
        Mod+7 { focus-workspace 7; }
        Mod+8 { focus-workspace 8; }
        Mod+9 { focus-workspace 9; }
        Mod+0 { focus-workspace 10; }

        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }
        Mod+Shift+4 { move-column-to-workspace 4; }
        Mod+Shift+5 { move-column-to-workspace 5; }
        Mod+Shift+6 { move-column-to-workspace 6; }
        Mod+Shift+7 { move-column-to-workspace 7; }
        Mod+Shift+8 { move-column-to-workspace 8; }
        Mod+Shift+9 { move-column-to-workspace 9; }
        Mod+Shift+0 { move-column-to-workspace 10; }

        Mod+Shift+E { quit; }

        Mod+W { spawn "${config.home.homeDirectory}/.local/bin/change-wallpaper"; }
        Mod+C { spawn "${config.home.homeDirectory}/.local/bin/ryoku-clipboard"; }
        Print { spawn "${config.home.homeDirectory}/.local/bin/ryoku-screenshot" "region"; }
        Mod+Print { spawn "${config.home.homeDirectory}/.local/bin/ryoku-screenshot" "full"; }

        Mod+N { spawn "${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc" "notifications" "toggle"; }
        Mod+Comma { spawn "${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc" "settings" "toggle"; }
        Mod+X { spawn "${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc" "powermenu" "toggle"; }
        Mod+Shift+X { spawn "${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc" "lock" "lock"; }

        XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
        XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
        XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
        XF86MonBrightnessUp { spawn "brightnessctl" "set" "+5%"; }
        XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
    }
  '';
in
{
  config = lib.mkIf enabled {
    xdg.configFile."niri/config.kdl".text = conf;

    home.packages = with pkgs; [
      niri
      xwayland-satellite
    ];

    home.file.".local/bin/ryoku-niri-session" = {
      source = ../../session/ryoku-niri-session;
      executable = true;
    };
  };
}
