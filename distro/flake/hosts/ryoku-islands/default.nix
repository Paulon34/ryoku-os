# Islands visual test host — same as ryoku/ but shellStyle = islands.
# Use for Debian Niri Islands validation without changing the quattro default.
# Bootstrap: --shell-style islands (writes hosts/<user>/default.nix likewise).
{
  username = "ryoku";
  homeDirectory = "/home/ryoku";
  profile = {
    edition = "minimal";
    visual = "balanced";
    shellStyle = "islands";
    jarvis = false;
  };
}
