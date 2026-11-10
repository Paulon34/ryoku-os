# Example / default host — Hyprland + Islands (test visual profile).
# Bootstrap writes hosts/<user>/default.nix for real users (git-add for flake purity).
{
  username = "ryoku";
  homeDirectory = "/home/ryoku";
  profile = {
    edition = "minimal";
    visual = "balanced";
    shellStyle = "islands";
    compositor = "hyprland";
    jarvis = false;
  };
}
