{ config, pkgs, lib, ... }:

# Shared Wayland session helpers (Niri + Hyprland). Always imported so either
# compositor can spawn NM/polkit/cliphist/launcher without depending on the
# other module's mkIf gate.
{
  home.file.".local/bin/ryoku-nm-applet" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      if command -v nm-applet >/dev/null 2>&1; then
        exec nm-applet --indicator
      fi
      echo "ryoku-nm-applet: nm-applet missing (install network-manager-gnome)" >&2
      exit 0
    '';
  };

  home.file.".local/bin/ryoku-polkit-agent" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      for cand in \
        /usr/libexec/polkit-mate-authentication-agent-1 \
        /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
        /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
        /usr/libexec/polkit-gnome-authentication-agent-1
      do
        if [[ -x "$cand" ]]; then
          exec "$cand"
        fi
      done
      echo "ryoku-polkit-agent: no GUI polkit agent found (install mate-polkit)" >&2
      exit 0
    '';
  };

  home.file.".local/bin/ryoku-cliphist-text" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      command -v wl-paste >/dev/null 2>&1 || exit 0
      command -v cliphist >/dev/null 2>&1 || exit 0
      exec wl-paste --type text --watch cliphist store
    '';
  };

  home.file.".local/bin/ryoku-cliphist-image" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      command -v wl-paste >/dev/null 2>&1 || exit 0
      command -v cliphist >/dev/null 2>&1 || exit 0
      exec wl-paste --type image --watch cliphist store
    '';
  };

  home.file.".local/bin/ryoku-launcher" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      ipc="${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc"
      if [[ -x "$ipc" ]]; then
        exec "$ipc" spotlight toggle
      fi
      if command -v dms >/dev/null 2>&1; then
        exec dms ipc call spotlight toggle
      fi
      exec fuzzel
    '';
  };

  home.file.".local/bin/ryoku-clipboard" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      ipc="${config.home.homeDirectory}/.local/bin/ryoku-dms-ipc"
      if [[ -x "$ipc" ]]; then
        exec "$ipc" clipboard toggle 2>/dev/null || true
        exit 0
      fi
      if command -v dms >/dev/null 2>&1; then
        exec dms ipc call clipboard toggle 2>/dev/null || true
      fi
      if command -v cliphist >/dev/null 2>&1; then
        cliphist list | fuzzel --dmenu | cliphist decode | wl-copy
      fi
    '';
  };

  home.file.".local/bin/ryoku-screenshot" = {
    executable = true;
    source = ../../scripts/ryoku-screenshot;
  };

  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/Pictures/Screenshots
    save_filename_format=ryoku-edited-%Y%m%d-%H%M%S.png
    show_panel=true
    early_exit=true
    line_size=5
    text_size=20
    text_font=sans-serif
    paint_mode=brush
    fill_shape=false
  '';

  home.packages = with pkgs; [
    grim
    slurp
    brightnessctl
    cliphist
  ];

  home.activation.ryokuScreenshotsDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/Pictures/Screenshots"
  '';
}
