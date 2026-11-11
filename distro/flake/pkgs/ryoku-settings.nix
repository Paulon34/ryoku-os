{
  lib,
  stdenv,
  cmake,
  qt6,
  git,
  wireplumber,
  brightnessctl,
  nix,
  desktop-file-utils,
  hyprland ? null,
  ryokuRepoPathDefault ? "",
  ryokuFlakeHostDefault ? "",
}:

stdenv.mkDerivation {
  pname = "ryoku-settings";
  version = "0.1.0-debian";

  src = ../../apps/ryoku-settings;

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    qt6.qttools
  ];

  nativeInstallCheckInputs = [ desktop-file-utils ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    desktop-file-validate "$out/share/applications/org.ryoku.Settings.desktop"
    test -x "$out/bin/ryoku-settings"
    grep -q '^Exec=ryoku-settings$' "$out/share/applications/org.ryoku.Settings.desktop"
    grep -q '^Terminal=false$' "$out/share/applications/org.ryoku.Settings.desktop"
    grep -q '^Icon=org.ryoku.Settings$' "$out/share/applications/org.ryoku.Settings.desktop"
    grep -q '^StartupWMClass=org.ryoku.Settings$' "$out/share/applications/org.ryoku.Settings.desktop"
    test -f "$out/share/icons/hicolor/scalable/apps/org.ryoku.Settings.svg"
    if grep -q '^X-GNOME-Autostart' "$out/share/applications/org.ryoku.Settings.desktop"; then
      echo "desktop entry must not enable autostart" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
    qt6.qtsvg
  ];

  cmakeFlags = [
    "-DRYOKU_SETTINGS_BUILD_TESTS=OFF"
  ]
  ++ lib.optional (ryokuRepoPathDefault != "")
    "-DRYOKU_REPO_PATH_DEFAULT=${ryokuRepoPathDefault}"
  ++ lib.optional (ryokuFlakeHostDefault != "")
    "-DRYOKU_FLAKE_HOST_DEFAULT=${ryokuFlakeHostDefault}";

  # Runtime tools via QProcess argv (no shell).
  # hyprctl comes from APT Hyprland on Debian; optional Nix hyprland for PATH.
  qtWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath (
      [ git wireplumber brightnessctl nix ]
      ++ lib.optional (hyprland != null) hyprland
    ))
  ];

  meta = {
    description = "Ryoku Settings — desktop configuration with privileged Apply (Debian Modular port)";
    homepage = "https://github.com/Paulon34/ryoku-os";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ryoku-settings";
  };
}
