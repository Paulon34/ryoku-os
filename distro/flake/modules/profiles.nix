{ config, lib, ... }:

# Profile knobs consumed by hosts/<user>/default.nix (preflight / ENTREGA C).
# Combinable axes already: edition × visual × shellStyle × jarvis.
# compositor is reserved for a future selectable stack — only niri is wired.
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
      default = "quattro";
      description = "Shell style (Quattro flat bar vs Islands).";
    };

    jarvis = lib.mkOption {
      type = lib.types.bool;
      # Off by default — Minimal must not enable Jarvis unless explicit.
      default = false;
      description = "Enable Jarvis bridge (default off).";
    };

    compositor = lib.mkOption {
      type = lib.types.enum [ "niri" "hyprland" ];
      default = "niri";
      description = ''
        Wayland compositor profile. Only "niri" is implemented on Debian Modular.
        "hyprland" is reserved (see distro/docs/COMPOSITOR.md); selecting it fails eval.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = config.ryoku.profile.compositor == "niri";
        message = ''
          ryoku.profile.compositor = "${config.ryoku.profile.compositor}" is not wired on
          Debian Modular yet. Keep compositor = "niri" (default). See distro/docs/COMPOSITOR.md.
        '';
      }
    ];
  };
}
