{ config, pkgs, lib, ... }:

# Hyprland primary compositor (Debian Modular).
# Target binary: APT trixie-backports hyprland ~0.55.x (NOT NixOS 0.56.2).
# Config uses hyprlang still supported on 0.55 + classic windowrulev2 /
# layerrule forms that 0.55.x accepts. Avoid 0.56-only windowrule rewrite
# (`float on, match:class`) and omit removed blur optimization keys.
# Session-scoped: only GDM "Ryoku (Hyprland)" starts Hyprland; Niri recovery
# stays installed via niri.nix (never exec-once niri here).
let
  cfg = config.ryoku.profile;
  enabled = cfg.compositor == "hyprland";
  quattro = cfg.shellStyle == "quattro";
  home = config.home.homeDirectory;
  ipc = "${home}/.local/bin/ryoku-dms-ipc";

  rounding = if quattro then 8 else 12;
  inactiveOpacity = if quattro then "1.0" else "0.96";
  shadowEnabled = if quattro then "false" else "true";

  quattroBeziers = ''
    bezier = linear,0,0,1,1
    bezier = almostLinear,0.5,0.5,0.75,1
    bezier = quick,0.15,0,0.1,1
  '';

  quattroAnims = ''
    animation = global,1,8,default
    animation = border,1,4.31,easeOutQuint
    animation = windows,1,3.03,easeOutQuint
    animation = windowsIn,1,3.28,easeOutQuint,popin 87%
    animation = windowsOut,1,1.19,linear,popin 87%
    animation = fadeIn,1,1.38,almostLinear
    animation = fadeOut,1,1.17,almostLinear
    animation = fade,1,2.42,quick
    animation = fadeSwitch,0
    animation = layers,1,3.05,easeOutQuint
    animation = layersIn,1,3.2,easeOutQuint,fade
    animation = layersOut,1,1.2,linear,fade
    animation = fadeLayersIn,1,1.43,almostLinear
    animation = fadeLayersOut,1,1.11,almostLinear
    animation = workspaces,0
  '';

  islandsAnims = ''
    animation = windows,1,5,easeOutQuint
    animation = windowsOut,1,4,easeInOutCubic,popin 80%
    animation = border,1,6,easeOutQuint
    animation = fade,1,5,easeOutQuint
    animation = workspaces,1,5,easeOutQuint
  '';

  # 0.55.x layerrule form (not 0.56 no_anim on, match:namespace …).
  quattroLayerRules = ''
    layerrule = noanim, ^(dms:.*)$
  '';

  conf = ''
    # Ryoku Hyprland — Debian Modular (shellStyle=${cfg.shellStyle})
    # Target: Debian trixie-backports hyprland ~0.55.x (hyprlang).
    # Borders from Matugen: ~/.config/ryoku/hyprland-colors.conf
    source = ~/.config/ryoku/hyprland-colors.conf

    $mod = SUPER
    $terminal = kitty
    $menu = ${ipc} spotlight toggle
    $fileManager = thunar

    monitor=,preferred,auto,1

    exec-once = ${home}/.local/bin/ryoku-nm-applet
    exec-once = ${home}/.local/bin/ryoku-polkit-agent
    exec-once = ${home}/.local/bin/ryoku-cliphist-text
    exec-once = ${home}/.local/bin/ryoku-cliphist-image
    exec-once = ${home}/.local/bin/ryoku-start-dms

    input {
        kb_layout = us
        numlock_by_default = true
        follow_mouse = 1
        touchpad {
            natural_scroll = true
            tap-to-click = true
        }
        sensitivity = 0
    }

    general {
        gaps_in = 5
        gaps_out = 10
        border_size = 2
        layout = dwindle
        resize_on_border = true
    }

    decoration {
        rounding = ${toString rounding}
        active_opacity = 1.0
        inactive_opacity = ${inactiveOpacity}
        blur {
            enabled = true
            size = 6
            passes = 2
        }
        shadow {
            enabled = ${shadowEnabled}
            range = 14
            render_power = 3
            offset = 0 3
            color = rgba(00000059)
            color_inactive = rgba(0000002e)
        }
    }

    animations {
        enabled = true
        bezier = easeOutQuint,0.23,1,0.32,1
        bezier = easeInOutCubic,0.65,0.05,0.36,1
        ${if quattro then quattroBeziers else ""}
        ${if quattro then quattroAnims else islandsAnims}
    }

    ${if quattro then quattroLayerRules else ""}

    misc {
        disable_hyprland_logo = true
        disable_splash_rendering = true
    }

    # Classic windowrulev2 (0.55.x). Avoid 0.56 rewrite: "float on, match:class …".
    windowrulev2 = float, class:^(xdg-desktop-portal-gtk)$
    windowrulev2 = center, class:^(xdg-desktop-portal-gtk)$
    windowrulev2 = size 900 620, class:^(xdg-desktop-portal-gtk)$
    windowrulev2 = float, class:^(org\.pulseaudio\.pavucontrol)$
    windowrulev2 = center, class:^(org\.pulseaudio\.pavucontrol)$
    windowrulev2 = size 920 640, class:^(org\.pulseaudio\.pavucontrol)$
    windowrulev2 = float, class:^(blueman-manager)$
    windowrulev2 = center, class:^(blueman-manager)$
    windowrulev2 = float, class:^(nm-connection-editor)$
    windowrulev2 = center, class:^(nm-connection-editor)$
    windowrulev2 = float, title:^(Open File|Save File|Open Folder|Select Folder|Save As|Abrir arquivo|Salvar arquivo|Abrir pasta|Selecionar pasta|Salvar como)$
    windowrulev2 = center, title:^(Open File|Save File|Open Folder|Select Folder|Save As|Abrir arquivo|Salvar arquivo|Abrir pasta|Selecionar pasta|Salvar como)$

    bind = $mod, RETURN, exec, $terminal
    bind = $mod, SPACE, exec, $menu
    bind = $mod, E, exec, $fileManager
    bind = $mod, Q, killactive,
    bind = $mod, F, fullscreen,
    bind = $mod, V, togglefloating,
    bind = $mod SHIFT, E, exit,

    bind = $mod, left, movefocus, l
    bind = $mod, right, movefocus, r
    bind = $mod, up, movefocus, u
    bind = $mod, down, movefocus, d
    bind = $mod, H, movefocus, l
    bind = $mod, L, movefocus, r
    bind = $mod, K, movefocus, u
    bind = $mod, J, movefocus, d

    bind = $mod SHIFT, H, movewindow, l
    bind = $mod SHIFT, L, movewindow, r
    bind = $mod SHIFT, K, movewindow, u
    bind = $mod SHIFT, J, movewindow, d

    bind = $mod, 1, workspace, 1
    bind = $mod, 2, workspace, 2
    bind = $mod, 3, workspace, 3
    bind = $mod, 4, workspace, 4
    bind = $mod, 5, workspace, 5
    bind = $mod, 6, workspace, 6
    bind = $mod, 7, workspace, 7
    bind = $mod, 8, workspace, 8
    bind = $mod, 9, workspace, 9
    bind = $mod, 0, workspace, 10

    bind = $mod SHIFT, 1, movetoworkspace, 1
    bind = $mod SHIFT, 2, movetoworkspace, 2
    bind = $mod SHIFT, 3, movetoworkspace, 3
    bind = $mod SHIFT, 4, movetoworkspace, 4
    bind = $mod SHIFT, 5, movetoworkspace, 5
    bind = $mod SHIFT, 6, movetoworkspace, 6
    bind = $mod SHIFT, 7, movetoworkspace, 7
    bind = $mod SHIFT, 8, movetoworkspace, 8
    bind = $mod SHIFT, 9, movetoworkspace, 9
    bind = $mod SHIFT, 0, movetoworkspace, 10

    bind = $mod, W, exec, ${home}/.local/bin/change-wallpaper
    bind = $mod, C, exec, ${home}/.local/bin/ryoku-clipboard
    bind = , Print, exec, ${home}/.local/bin/ryoku-screenshot region
    bind = $mod, Print, exec, ${home}/.local/bin/ryoku-screenshot full
    bind = $mod, N, exec, ${ipc} notifications toggle
    bind = $mod, comma, exec, ${ipc} settings toggle
    bind = $mod, X, exec, ${ipc} powermenu toggle
    bind = $mod SHIFT, X, exec, ${ipc} lock lock

    bindm = $mod, mouse:272, movewindow
    bindm = $mod, mouse:273, resizewindow

    bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
    bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindel = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    bindel = , XF86MonBrightnessUp, exec, brightnessctl set +5%
    bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
  '';
in
{
  # Session wrapper always installed so GDM can launch Hyprland even if the
  # HM profile compositor knob is temporarily niri (recovery swap).
  home.file.".local/bin/ryoku-hyprland-session" = {
    source = ../../session/ryoku-hyprland-session;
    executable = true;
  };

  config = lib.mkIf enabled {
    # APT provides Hyprland; HM only manages the conf Hyprland reads by default.
    xdg.configFile."hypr/hyprland.conf".text = conf;

    home.sessionVariables = {
      XDG_CURRENT_DESKTOP = "Hyprland:Ryoku";
      XDG_SESSION_DESKTOP = "Hyprland";
    };

    xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".text = ''
      [preferred]
      default=hyprland;gtk;wlr;
    '';
  };
}
