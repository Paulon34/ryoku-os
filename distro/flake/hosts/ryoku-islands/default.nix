# Islands + Hyprland reference host (same defaults as ryoku/).
# Select Quattro with --shell-style quattro; Niri recovery with --compositor niri.
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
