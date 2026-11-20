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

  # Unit tests link ops.c from the sibling apply helper (outside src).
  postUnpack = ''
    mkdir -p "$sourceRoot/../ryoku-settings-apply/src"
    cp -a ${../../apps/ryoku-settings-apply/src/ops.c} \
      "$sourceRoot/../ryoku-settings-apply/src/ops.c"
    cp -a ${../../apps/ryoku-settings-apply/src/ops.h} \
      "$sourceRoot/../ryoku-settings-apply/src/ops.h"
  '';

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    qt6.qttools
  ];

  nativeInstallCheckInputs = [ desktop-file-utils ];
  doCheck = true;
  doInstallCheck = true;

  # Unit tests (72) — built alongside the app when RYOKU_SETTINGS_BUILD_TESTS=ON.
  checkPhase = ''
    runHook preCheck
    export QT_QPA_PLATFORM=offscreen
    export QT_QUICK_BACKEND=software
    export HOME="$TMPDIR/ryoku-settings-check-home"
    export XDG_RUNTIME_DIR="$TMPDIR/ryoku-settings-check-xdg"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    if [ -x ./ryoku-settings-tests ]; then
      ./ryoku-settings-tests
    elif [ -x ./tests/ryoku-settings-tests ]; then
      ./tests/ryoku-settings-tests
    else
      echo "ryoku-settings-tests binary missing from build dir" >&2
      ls -la
      exit 1
    fi
    runHook postCheck
  '';

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
    # Headless QML smoke: real engine load (catches QTP0001 / RESOURCE_PREFIX regressions).
    export QT_QPA_PLATFORM=offscreen
    export QT_QUICK_BACKEND=software
    export HOME="$TMPDIR/ryoku-settings-smoke-home"
    export XDG_RUNTIME_DIR="$TMPDIR/ryoku-settings-smoke-xdg"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    "$out/bin/ryoku-settings" --smoke-test
    runHook postInstallCheck
  '';

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
    qt6.qtsvg
  ];

  # Qt6::Test for ryoku-settings-tests (checkPhase).
  nativeCheckInputs = [ qt6.qtbase ];

  cmakeFlags = [
    "-DRYOKU_SETTINGS_BUILD_TESTS=ON"
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
