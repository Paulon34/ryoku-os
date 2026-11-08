{ config, lib, pkgs, ... }:

# Full edition: extra desktop utilities (still no unfree by default).
lib.mkIf (config.ryoku.profile.edition == "full") {
  home.packages = with pkgs; [
    btop
    jq
    ripgrep
    fd
    git
  ];

  home.sessionVariables.RYOKU_EDITION = "full";
}
