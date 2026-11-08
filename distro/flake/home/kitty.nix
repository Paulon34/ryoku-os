{ pkgs, ... }:

{
  programs.kitty = {
    enable = true;
    package = pkgs.kitty;
    settings = {
      font_family = "DejaVu Sans Mono";
      font_size = 11;
      background_opacity = "0.95";
      confirm_os_window_close = 0;
      wayland_titlebar_color = "background";
    };
  };
}
