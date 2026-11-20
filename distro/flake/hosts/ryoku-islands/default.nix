# Islands + Hyprland reference host (same defaults as ryoku/).
# Select Quattro with --shell-style quattro; Niri recovery with --compositor niri.
# settingsApply.repoPath empty on example hosts — bootstrap fills it for real users.
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
