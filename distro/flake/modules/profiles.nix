{ lib, ... }:

# Shared profile options — Lite/Balanced/Ultra × Minimal/Full (ENTREGA C).
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
      description = "Visual/performance profile (blur/effects budget).";
    };

    shellStyle = lib.mkOption {
      type = lib.types.enum [ "quattro" "islands" ];
      default = "quattro";
      description = "DMS shell style.";
    };

    jarvis = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Jarvis bridge (off by default; keep off on Minimal).";
    };
  };
}
