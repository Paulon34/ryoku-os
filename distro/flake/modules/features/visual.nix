{ config, lib, ... }:

# Map Lite/Balanced/Ultra → DMS/session hints (ENTREGA C).
let
  v = config.ryoku.profile.visual;
  budget =
    if v == "lite" then
      {
        blur = false;
        animations = "minimal";
        videoWallpaper = false;
      }
    else if v == "ultra" then
      {
        blur = true;
        animations = "rich";
        videoWallpaper = true;
      }
    else
      {
        blur = true;
        animations = "standard";
        videoWallpaper = false;
      };
in
{
  # Propagate into ryoku settings consumed by DMS patches.
  xdg.configFile."ryoku/profile.json".text = builtins.toJSON {
    edition = config.ryoku.profile.edition;
    visual = v;
    shellStyle = config.ryoku.profile.shellStyle;
    jarvis = config.ryoku.profile.jarvis;
    budget = budget;
  };

  home.sessionVariables.RYOKU_VISUAL_PROFILE = v;
}
