{
  config,
  pkgs,
  lib,
  nixGL,
  ...
}:

# nixGL wrappers for OpenGL/Vulkan apps from the Nix store on Debian.
let
  # Prefer Intel/Mesa wrapper; Default covers common free drivers.
  wrappers = nixGL.packages.${pkgs.stdenv.hostPlatform.system};
  nixGLDefault = wrappers.nixGLDefault or wrappers.nixGLIntel;
in
{
  home.packages = lib.optionals (nixGLDefault != null) [ nixGLDefault ];

  home.file.".local/bin/ryoku-nixgl" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # Thin launcher: prefer nixGLDefault from HM profile.
      WRAP="${config.home.homeDirectory}/.nix-profile/bin/nixGLDefault"
      HM_WRAP="${config.home.homeDirectory}/.local/state/nix/profiles/home-manager/home-path/bin/nixGLDefault"
      if [[ -x "$HM_WRAP" ]]; then
        exec "$HM_WRAP" "$@"
      elif [[ -x "$WRAP" ]]; then
        exec "$WRAP" "$@"
      else
        # Fallback: run unwrapped (host Mesa may work for some apps).
        exec "$@"
      fi
    '';
  };
}
