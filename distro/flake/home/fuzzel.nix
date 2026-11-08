{ pkgs, ... }:

# Launcher: APT installs fuzzel; HM keeps a consistent config.
# If APT fuzzel is present, PATH wins for spawn; this package is a fallback.
{
  home.packages = [ pkgs.fuzzel ];

  xdg.configFile."fuzzel/fuzzel.ini".text = ''
    [main]
    font=DejaVu Sans:size=12
    dpi-aware=yes
    fields=filename,name,generic
    terminal=kitty -e
    prompt="ryoku> "
    layer=overlay

    [colors]
    background=1a1a1add
    text=e8e8e8ff
    match=8ab4f8ff
    selection=333333ff
    selection-text=ffffffff
    border=8a9099ff
  '';
}
