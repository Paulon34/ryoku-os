# Example / default host — Hyprland + Islands (test visual profile).
# Bootstrap writes hosts/<user>/default.nix for real users (git-add for flake purity).
# settingsApply.repoPath must be absolute for privileged Settings Apply; leave
# empty on the example host so CI does not bake a fake checkout path.
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
  settingsApply = {
    repoPath = "";
    flakeHost = "ryoku";
  };
}
