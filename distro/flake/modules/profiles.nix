{ lib, ... }:

# Profile knobs consumed by hosts/<user>/default.nix (preflight / ENTREGA C).
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
  };
}
