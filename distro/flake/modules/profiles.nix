{ config, lib, ... }:

# Profile knobs consumed by hosts/<user>/default.nix.
# Axes: edition × visual × shellStyle × jarvis × compositor.
# After this Hyprland port: compositor default = hyprland; niri remains a
# selectable recovery session (GDM still installs both .desktop files).
{
  options.ryoku.profile = {
    edition = lib.mkOption {
      type = lib.types.enum [ "minimal" "full" ];
      default = "minimal";
      description = "Package edition: minimal desktop vs full extras.";
    };

    visual = lib.mkOption {
      type = lib.types.enum [ "lite" "balanced" "ultra" ];
      default = "balanced";
      description = "Visual/performance profile.";
    };

    shellStyle = lib.mkOption {
      type = lib.types.enum [ "quattro" "islands" ];
      default = "islands";
      description = "Shell style (Islands floating capsules vs Quattro flat bar).";
    };

    jarvis = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Jarvis bridge (default off).";
    };

    compositor = lib.mkOption {
      type = lib.types.enum [ "hyprland" "niri" ];
      default = "hyprland";
      description = ''
        Wayland compositor. Default hyprland (APT trixie-backports ~0.55.x).
        niri remains available as a GDM recovery session — see distro/docs/COMPOSITOR.md.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.elem config.ryoku.profile.compositor [ "hyprland" "niri" ];
        message = "ryoku.profile.compositor must be hyprland or niri";
      }
    ];
  };
}
