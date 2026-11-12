{
  config,
  pkgs,
  lib,
  dankMaterialShell,
  nixGL,
  ...
}:

# DankMaterialShell on Niri — standalone HM (no osConfig).
# Reuses Ryoku Desktop Quattro/Islands bar prefs; adapts IPC/startup for
# Debian GDM → `niri --session` (no graphical-session.target / dms.service).
let
  shellStyle = config.ryoku.profile.shellStyle;
  visualProfile = config.ryoku.profile.visual;
  quattro = shellStyle == "quattro";

  dmsPkgs = dankMaterialShell.packages.${pkgs.stdenv.hostPlatform.system};

  dmsPackage = pkgs.callPackage ../pkgs/dms-shell-ryoku.nix {
    dms-shell = dmsPkgs.dms-shell;
    ryokuSettingsJson = "${config.home.homeDirectory}/.config/ryoku/settings.json";
    ryokuShellStyle = shellStyle;
  };

  dmsBin = "${dmsPackage}/bin/dms";
  jq = lib.getExe pkgs.jq;

  # DMS Go always exec.Command("qs", …) for ipc/list/help (shell.go).
  # Session children get this via ryoku-start-dms; SSH/systemd oneshots do not
  # unless every dms entrypoint prepends Quickshell. Keep declarative — never
  # patch /nix/store.
  dmsRuntimePath = lib.makeBinPath [
    pkgs.quickshell
    dmsPackage
    pkgs.matugen
    pkgs.jq
  ];

  # User-facing `dms` so SSH `dms ipc …` and HM profile lookups find qs.
  dmsCli = pkgs.writeShellScriptBin "dms" ''
    export PATH="${dmsRuntimePath}:''${PATH:-}"
    exec "${dmsBin}" "$@"
  '';

  # Bar defaults from ryoku-desktop home/dms.nix (Quattro = Omarchy flat strip).
  # ShellCore.qml only activates DankBar when barConfig.enabled is true
  # (`active: … && (barConfig?.enabled ?? false)`). Omitting enabled leaves the
  # loader dead → no PanelWindow / WlrLayershell Top surface (Niri layers empty
  # on Top/Bottom/Overlay while IPC still reports settings.visible).
  # position must be SettingsData.Position int (0=Top); missing → getPosition "unknown".
  styleBar =
    if quattro then
      {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0; # SettingsData.Position.Top
        screenPreferences = [ "all" ];
        showOnLastDisplay = true;
        visible = true;
        autoHide = false;
        noBackground = false;
        transparency = 0.96;
        widgetTransparency = 0;
        spacing = 0;
        innerPadding = 1;
        widgetPadding = 6;
        fontScale = 1.1;
        squareCorners = true;
        gothCornersEnabled = false;
        borderEnabled = false;
        widgetOutlineEnabled = false;
        shadowIntensity = 0;
        popupGapsAuto = false;
        popupGapsManual = 5;
        leftWidgets = [
          "launcherButton"
          "workspaceSwitcher"
        ];
        centerWidgets = [ "clock" ];
        rightWidgets = [
          "systemTray"
          "notificationButton"
          "controlCenterButton"
          "battery"
        ];
      }
    else
      {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0; # SettingsData.Position.Top
        screenPreferences = [ "all" ];
        showOnLastDisplay = true;
        visible = true;
        autoHide = false;
        noBackground = true;
        transparency = 1;
        widgetTransparency = 0.92;
        spacing = 10;
        innerPadding = 4;
        widgetPadding = 6;
        fontScale = 1;
        squareCorners = false;
        borderEnabled = false;
        widgetOutlineEnabled = false;
        shadowIntensity = 0;
        popupGapsAuto = true;
        leftWidgets = [
          "launcherButton"
          "workspaceSwitcher"
          "focusedWindow"
        ];
        centerWidgets = [ "clock" ];
        rightWidgets = [
          "systemTray"
          "notificationButton"
          "battery"
          "controlCenterButton"
        ];
      };

  styleSettings =
    if quattro then
      {
        cornerRadius = 8;
        popupTransparency = 0.97;
        notificationPopupShadowEnabled = false;
        dankLauncherV2BorderEnabled = false;
        modalDarkenBackground = true;
        powerMenuGridLayout = false;
        lockScreenShowProfileImage = false;
        launcherLogoMode = "os";
        launcherLogoColorOverride = "primary";
      }
    else
      {
        cornerRadius = 16;
        launcherLogoMode = "apps";
        launcherLogoColorOverride = "";
        notificationPopupShadowEnabled = true;
        lockScreenShowProfileImage = true;
        popupTransparency = 0.88;
      };

  # Top-level DMS prefs from ryoku-desktop (SettingsSpec keys only).
  ryokuBarPatch = pkgs.writeText "ryoku-dms-bar-patch.json" (
    builtins.toJSON (
      styleSettings
      // {
        widgetBackgroundColor = "sc";
        workspaceColorMode = "primary";
        focusedWindowCompactMode = true;
        focusedWindowSize = 0;
        clockCompactMode = false;
        showSeconds = false;
        showWorkspaceIndex = false;
        showWorkspaceApps = false;
        showWorkspaceName = false;
        barElevationEnabled = false;
        showMusic = false;
        showWeather = false;
        showCpuUsage = false;
        showMemUsage = false;
        showClipboard = false;
        showLauncherButton = true;
        showWorkspaceSwitcher = true;
        showFocusedWindow = true;
        showClock = true;
        showSystemTray = true;
        showNotificationButton = true;
        showBattery = true;
        showControlCenterButton = true;
        animationSpeed = 1;
        popoutAnimationSpeed = 1;
        syncComponentAnimationSpeeds = true;
        waveProgressEnabled = false;
        weatherEnabled = false;
        useAutoLocation = false;
      }
    )
  );

  ryokuDefaultBar = pkgs.writeText "ryoku-dms-default-bar.json" (builtins.toJSON styleBar);

  defaultWallpaper = "${config.home.homeDirectory}/.local/share/wallpapers/ryoku-night.jpg";

  # Seed only when missing — file must stay mutable for DMS + Matugen.
  ryokuSettingsSeed = pkgs.writeText "ryoku-dms-settings-seed.json" (
    builtins.toJSON (
      styleSettings
      // {
        barConfigs = [ styleBar ];
        currentWallpaper = defaultWallpaper;
        # Material You: DMS must use wallpaper-derived colors, not the stock
        # purple theme. Subsequent HM activation reads the Ryoku preference.
        currentThemeName = "dynamic";
        currentThemeCategory = "dynamic";
        runUserMatugenTemplates = true;
      }
    )
  );

  # No dms.service on Debian GDM/Niri — wait for IPC directly.
  # Absolute dms still LookPath("qs"); PATH must include Quickshell here too.
  dmsIpcHelper = ''
    dms_ipc() {
      [ -n "''${XDG_RUNTIME_DIR:-}" ] || return 1
      export PATH="${dmsRuntimePath}:''${PATH:-}"
      for _ in $(${pkgs.coreutils}/bin/seq 120); do
        if ${dmsBin} ipc call "$@" >/dev/null 2>&1; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.5
      done
      return 1
    }
  '';

  applyRyokuBar = pkgs.writeShellScript "apply-ryoku-dms-bar" ''
    set -euo pipefail
    ${dmsIpcHelper}

    settings="$HOME/.config/DankMaterialShell/settings.json"
    patch=${ryokuBarPatch}
    jq=${jq}

    mkdir -p "$HOME/.config/DankMaterialShell"

    if [ ! -f "$settings" ]; then
      echo "Ryoku DMS: settings.json missing; skipping bar patch" >&2
      exit 0
    fi

    before=$(${pkgs.coreutils}/bin/sha256sum < "$settings")

    # The checkbox in Ryoku Settings is stored in the writable repo settings,
    # not in the Home Manager seed at ~/.config/ryoku/settings.json.
    # Explicit false keeps stock colors; missing/true defaults to Material You.
    ryoku_settings=${lib.escapeShellArg (if config.ryoku.settingsApply.repoPath != "" then "${config.ryoku.settingsApply.repoPath}/ryoku/settings.json" else "")}
    dynamic=true
    if [[ -n "$ryoku_settings" && -f "$ryoku_settings" ]]; then
      dynamic=$("$jq" -r 'if .appearance.dynamicColors == false then "false" else "true" end' "$ryoku_settings" 2>/dev/null || echo true)
    fi

    # DMS 1.5.3 barConfigs is an ARRAY of { id, ... }. Object maps are ignored.
    "$jq" --argjson dynamic "$dynamic" -s '
      .[0] as $s | .[1] as $p | .[2] as $bar |
      ($s + $p) |
      .barConfigs = (
        ((.barConfigs // []) | if type == "array" then . else [] end) as $cfgs |
        if ($cfgs | map(select(.id == "default")) | length) > 0 then
          $cfgs | map(if .id == "default" then . + $bar else . end)
        else
          $cfgs + [$bar]
        end
      ) |
      if $dynamic then
        .currentThemeName = "dynamic" |
        .currentThemeCategory = "dynamic" |
        .runUserMatugenTemplates = true
      elif .currentThemeName == "dynamic" then
        .currentThemeName = "purple" | .currentThemeCategory = "generic"
      else . end
    ' "$settings" "$patch" ${ryokuDefaultBar} > "$settings.tmp"

    mv "$settings.tmp" "$settings"

    changed=1
    [ "$(${pkgs.coreutils}/bin/sha256sum < "$settings")" != "$before" ] || changed=0

    if dms_ipc ryoku refreshSettings; then
      echo "Ryoku DMS: running shell reloaded settings.json"
    elif [ "$changed" = 1 ]; then
      echo "Ryoku DMS: settings updated; re-login or restart DMS to apply bar" >&2
    fi
  '';

  applyRyokuSession = pkgs.writeShellScript "apply-ryoku-dms-session" ''
    set -euo pipefail
    ${dmsIpcHelper}

    session="''${XDG_STATE_HOME:-$HOME/.local/state}/DankMaterialShell/session.json"
    jq=${jq}
    wallpaper=${lib.escapeShellArg defaultWallpaper}

    if [ ! -f "$session" ]; then
      echo "Ryoku DMS: session.json missing; skipping wallpaper seed" >&2
      exit 0
    fi

    if [ -n "$wallpaper" ] && [ -f "$wallpaper" ] \
      && [ -z "$("$jq" -r '.wallpaperPath // ""' "$session")" ]; then
      "$jq" --arg w "$wallpaper" '. + {wallpaperPath: $w}' "$session" > "$session.tmp"
      mv "$session.tmp" "$session"
      dms_ipc wallpaper set "$wallpaper" && echo "Ryoku DMS: first wallpaper set" || true
    fi
  '';
in
{
  home.packages = [
    dmsCli # wraps store dms so `dms ipc` always finds qs (SSH + login)
    pkgs.quickshell # `qs` on HM profile for diagnostics; also in dmsRuntimePath
    pkgs.matugen
    pkgs.jq
  ];

  # Managed Ryoku prefs (not the mutable DMS settings.json).
  xdg.configFile."ryoku/settings.json".text = builtins.toJSON {
    appearance = {
      shellStyle = shellStyle;
      visualProfile = visualProfile;
      wallpaper = "ryoku-night.jpg";
    };
  };

  # Seed mutable DMS settings once. Never use xdg.configFile here — that would
  # symlink a read-only store path and break DMS persistence + Quattro merges.
  home.activation.seedRyokuDmsSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.config/DankMaterialShell/settings.json"
    run mkdir -p "$HOME/.config/DankMaterialShell"
    if [ ! -f "$settings" ]; then
      run install -m 644 ${ryokuSettingsSeed} "$settings"
      echo "Ryoku DMS: seeded Quattro/Islands settings.json"
    fi
  '';

  home.activation.applyRyokuDmsBar = lib.hm.dag.entryAfter [ "seedRyokuDmsSettings" ] ''
    run ${applyRyokuBar}
  '';

  home.activation.applyRyokuDmsSession = lib.hm.dag.entryAfter [ "applyRyokuDmsBar" ] ''
    run ${applyRyokuSession}
  '';

  # Path units still help on sessions that reach default.target; GDM direct
  # niri may not, so activation + seed above are the primary path.
  systemd.user.paths.ryoku-dms-bar = {
    Unit.Description = "Apply the Ryoku bar to DMS once its settings exist";
    Path.PathExists = "%h/.config/DankMaterialShell/settings.json";
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.ryoku-dms-bar = {
    Unit.Description = "Apply the Ryoku bar and shell style to DMS";
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${applyRyokuBar}";
    };
  };

  systemd.user.paths.ryoku-dms-session = {
    Unit.Description = "Apply Ryoku wallpaper to DMS once its session exists";
    Path.PathExists = "%S/DankMaterialShell/session.json";
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.ryoku-dms-session = {
    Unit.Description = "Apply the Ryoku first wallpaper to DMS";
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${applyRyokuSession}";
    };
  };

  # Absolute-path IPC helper for Niri binds (GDM may omit HM profile PATH).
  home.file.".local/bin/ryoku-dms-ipc" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      export PATH="${dmsRuntimePath}:$PATH"
      exec "${dmsBin}" ipc call "$@"
    '';
  };

  # The tested GDM session invokes 'niri --session' directly, not via
  # niri-session / niri.service; graphical-session.target is not guaranteed.
  # Spawn DMS from Niri after WAYLAND_DISPLAY is ready.
  # Do NOT also enable a competing systemd user service (double instance).
  home.file.".local/bin/ryoku-start-dms" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      # GDM/Niri may not inherit the Home Manager profile PATH. The DMS Go
      # launcher spawns 'qs', while QML subprocesses also call 'dms' by name
      # (auth/blur/IPC). Export BOTH binaries to the entire child process tree.
      export PATH="${dmsRuntimePath}:$PATH"

      # Hyprland exec-once has no interactive stderr. Persist local startup logs
      # to distinguish missing autostart from early DMS/Qt failures.
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/ryoku"
      ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
      exec >>"$state_dir/dms-startup.log" 2>&1
      echo "=== ryoku-start-dms $(${pkgs.coreutils}/bin/date -Is) ==="
      echo "WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-unset}; XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-unset}"

      # GDM must supply the compositor session environment; never invent it.
      if [[ -z "''${XDG_RUNTIME_DIR:-}" ]]; then
        echo "ryoku-start-dms: XDG_RUNTIME_DIR unset"
        exit 1
      fi
      if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
        echo "ryoku-start-dms: WAYLAND_DISPLAY unset"
        exit 1
      fi
      if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        echo "ryoku-start-dms: warning: DBUS_SESSION_BUS_ADDRESS unset"
      fi

      # Wait for the compositor socket at first login, rather than racing it.
      socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
      for ((i=0; i<40; i++)); do
        [[ -S "$socket" ]] && break
        ${pkgs.coreutils}/bin/sleep 0.25
      done
      if [[ ! -S "$socket" ]]; then
        echo "ryoku-start-dms: missing Wayland socket $socket"
        exit 1
      fi

      # This is the ONLY managed DMS entry point for Hyprland/Niri. The
      # per-user flock (held throughout DMS execution) prevents duplicates.
      # Do not use broad "pgrep -f quickshell" as a startup veto: real guest
      # login saw a transient false positive here and stayed black, with no
      # DMS/Quickshell process or layers surviving after login.
      uid=$(${pkgs.coreutils}/bin/id -u)
      lock="''${XDG_RUNTIME_DIR}/ryoku-dms.start.lock"
      exec 9>"$lock" || {
        echo "ryoku-start-dms: cannot open lock $lock"
        exit 1
      }
      if ! ${pkgs.util-linux}/bin/flock -n 9; then
        echo "ryoku-start-dms: another managed DMS instance holds flock for uid $uid; skipping"
        exit 0
      fi
      echo "ryoku-start-dms: acquired session flock (uid=$uid)"

      # When the DMS launcher exits very early, Quickshell might still be
      # alive on its own. Only an actual Quickshell executable can veto a
      # retry; command-line substring matches wrongly catch shell/helpers.
      quickshell_alive() {
        local pid exe
        while IFS= read -r pid; do
          [[ -n "$pid" && "$pid" != "$$" ]] || continue
          exe=$(${pkgs.coreutils}/bin/readlink -f "/proc/$pid/exe" 2>/dev/null || true)
          case "$exe" in
            */bin/quickshell|*/bin/.quickshell-wrapped|*/bin/qs)
              echo "ryoku-start-dms: active Quickshell exe=$exe pid=$pid"
              return 0
              ;;
          esac
        done < <(${pkgs.procps}/bin/pgrep -u "$uid" -f -- 'quickshell|/bin/qs' || true)
        return 1
      }

      # Async bar IPC retries must not inherit fd9. Otherwise a failed DMS
      # start leaves its flock held by the helper for up to ~60 seconds.
      (
        ${pkgs.coreutils}/bin/sleep 2
        ${applyRyokuBar} || true
        ${applyRyokuSession} || true
      ) 9>&- &

      # If startup fails immediately due to an early graphics/DBus race,
      # retry ONCE. Never restart after a normal long-running session exits.
      for attempt in 1 2; do
        started=$(${pkgs.coreutils}/bin/date +%s)
        echo "ryoku-start-dms: starting DMS attempt=$attempt"
        if "${nixGL.packages.${pkgs.stdenv.hostPlatform.system}.nixGLIntel}/bin/nixGLIntel" "${dmsBin}" run; then
          rc=0
        else
          rc=$?
        fi
        elapsed=$(( $(${pkgs.coreutils}/bin/date +%s) - started ))
        echo "ryoku-start-dms: DMS exited rc=$rc elapsed=''${elapsed}s"
        if [[ "$elapsed" -ge 15 || "$attempt" -eq 2 ]]; then
          exit "$rc"
        fi
        if quickshell_alive; then
          echo "ryoku-start-dms: Quickshell still active; not launching duplicate"
          exit "$rc"
        fi
        ${pkgs.coreutils}/bin/sleep 3
      done
    '';
  };
}
