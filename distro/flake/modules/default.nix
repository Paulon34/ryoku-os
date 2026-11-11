{ ... }:

# Module groups: profiles (edition/visual/shell/compositor) + future Full extras.
# APT package groups live under distro/apt/ (packages-base / packages-full /
# packages-hyprland) and are consumed by ryoku-bootstrap — not by HM eval.
{
  imports = [
    ./profiles.nix
  ];
}
