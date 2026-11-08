{ config, lib, pkgs, ... }:

# Minimal edition: desktop shell only, no gaming/dev extras.
lib.mkIf (config.ryoku.profile.edition == "minimal") {
  home.packages = with pkgs; [
    # Intentionally small — APT covers kitty/thunar/fuzzel.
  ];

  # Jarvis stays off unless explicitly enabled (default false).
  home.sessionVariables.RYOKU_JARVIS = lib.mkDefault (
    if config.ryoku.profile.jarvis then "1" else "0"
  );
}
