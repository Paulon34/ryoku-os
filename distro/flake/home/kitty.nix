{ pkgs, ... }:

# Kitty parity with ryoku-desktop (JetBrainsMono Nerd Font). Fish shell is
# optional on Debian Minimal — leave default login shell alone.
{
  programs.kitty = {
    enable = true;
    package = pkgs.kitty;

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };

    settings = {
      confirm_os_window_close = 0;
      background_opacity = "0.90";
      window_padding_width = 12;
      enable_audio_bell = false;
      visual_bell_duration = "0.08";
      window_alert_on_bell = false;
      scrollback_lines = 10000;
      cursor_shape = "beam";
      cursor_blink_interval = 0;
      wayland_titlebar_color = "background";
    };

    # DMS may drop dank-theme.conf after Matugen; include is optional at runtime.
    extraConfig = ''
      include dank-theme.conf
    '';

    keybindings = {
      "ctrl+shift+enter" = "new_window";
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+w" = "close_tab";
      "ctrl+shift+left" = "previous_tab";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
    };
  };

  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];
}
