# Example / default host — committed so the flake always has a pure attr.
# Bootstrap writes hosts/<user>/default.nix for real users (git-add for flake purity).
{
  username = "ryoku";
  homeDirectory = "/home/ryoku";
  profile = {
    edition = "minimal";
    visual = "balanced";
    shellStyle = "quattro";
    jarvis = false;
  };
}
