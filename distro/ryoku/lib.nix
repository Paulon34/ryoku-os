# Shared Ryoku settings loader (Nix).
#
# Ownership: ryoku/settings.json is the Git-versioned source of truth for
# keys migrated to Ryoku Settings. null / missing = keep existing Nix/HM/DMS
# configuration. Nix modules only project known keys; they never generate
# arbitrary Nix from the GUI.
#
# Unknown JSON keys are preserved in the file (schema additionalProperties)
# but ignored by these helpers until a future schemaVersion consumes them.
#
# Migrations: schemaVersion is checked here. v1→v2 transforms are not
# implemented yet — bump will fail eval until a migration is added.
#
# Apply (Phase 7G-A + RC login wallpaper):
#   applySubset / settingsHash cover ONLY keys that Nix modules actually
#   consume today. Saving a key that is not projected must NOT change the
#   hash (and therefore must not show Needs Apply).

{ lib }:

let
  settingsPath = ./settings.json;
  wallpapersDir = ../assets/wallpapers;

  raw = builtins.fromJSON (builtins.readFile settingsPath);

  supportedSchemaVersion = 1;

  # Basename-only wallpaper id (same contract as SettingsStore::isValidWallpaperId).
  wallpaperIdOk =
    id:
    builtins.isString id
    && builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*\\.(jpg|jpeg|png|webp)" id != null
    && !(builtins.match ".*\\.\\..*" id != null)
    && !(lib.hasInfix "/" id)
    && !(lib.hasInfix "\\" id);

  # Fail clearly on incompatible majors (future GUI/migrations).
  checked =
    if !(builtins.isAttrs raw) then
      throw "ryoku/settings.json: root must be a JSON object"
    else if !(raw ? schemaVersion) then
      throw "ryoku/settings.json: missing schemaVersion"
    else if raw.schemaVersion != supportedSchemaVersion then
      throw (
        "ryoku/settings.json: unsupported schemaVersion ${toString raw.schemaVersion} "
        + "(this tree supports ${toString supportedSchemaVersion})"
      )
    else
      raw;

  appearance = checked.appearance or { };
  apps = checked.apps or { };
  desktop = checked.desktop or { };
  display = checked.display or { };
  weather = checked.weather or { };
  hyprland = desktop.hyprland or { };

  # null-preserving getters (JSON null → Nix null).
  get = path: default: lib.attrByPath path default checked;

  # True when the key is present and not JSON/Nix null.
  isSet = value: value != null;

  # Prefer Ryoku value when set; otherwise keep the existing fallback.
  orExisting = value: existing: if isSet value then value else existing;

  # Flatpak application IDs declared by Ryoku Settings (may be []).
  flatpakDeclared =
    let
      rawList = apps.flatpakDeclared or [ ];
    in
    if builtins.isList rawList then rawList else [ ];

  # Deterministic sort for hash stability (C++ SettingsStore also sorts).
  flatpakDeclaredSorted = lib.lists.sort (a: b: a < b) flatpakDeclared;

  # SDDM / login wallpaper — managed gallery basename only.
  # null / missing → keep theme embedded background (no hash contribution).
  loginWallpaperRaw = appearance.loginWallpaper or null;

  loginWallpaper =
    if loginWallpaperRaw == null then
      null
    else if !(wallpaperIdOk loginWallpaperRaw) then
      throw (
        "ryoku/settings.json: appearance.loginWallpaper must be a Ryoku gallery "
        + "basename (e.g. \"5.jpg\"), got: ${builtins.toJSON loginWallpaperRaw}"
      )
    else if !(builtins.pathExists (wallpapersDir + "/${loginWallpaperRaw}")) then
      throw (
        "ryoku/settings.json: appearance.loginWallpaper \"${loginWallpaperRaw}\" "
        + "not found under assets/wallpapers/"
      )
    else
      loginWallpaperRaw;

  # Store path for SDDM (only when set). Path context copies into the Nix store.
  loginWallpaperPath =
    if loginWallpaper == null then null else wallpapersDir + "/${loginWallpaper}";

  # Weather place name, resolved by DMS's built-in Open-Meteo geocoding.
  # Personal value: lives only in settings.json, never as a Nix default.
  # null / missing / blank → weather hidden in DMS (no fetch, no fallback city).
  weatherLocationRaw = weather.location or null;

  weatherLocation =
    if weatherLocationRaw == null then
      null
    else if !(builtins.isString weatherLocationRaw) then
      throw (
        "ryoku/settings.json: weather.location must be a string or null, got: "
        + builtins.toJSON weatherLocationRaw
      )
    else
      let
        trimmed = lib.strings.trim weatherLocationRaw;
      in
      if trimmed == "" then
        null
      else if builtins.stringLength trimmed > 100 then
        throw "ryoku/settings.json: weather.location must be at most 100 characters"
      else if builtins.match "[^[:cntrl:]]*" trimmed == null then
        throw "ryoku/settings.json: weather.location must not contain control characters"
      else
        trimmed;

  # -------------------------------------------------------------------------
  # Shell style: "quattro" (default; Omarchy Quattro-inspired flat bar and
  # framed cards) or "islands" (floating pill bar). Baked into the DMS build
  # (modules/desktop.nix) and the bar layout (home/dms.nix), so it is applied
  # with a rebuild like the login wallpaper.
  shellStyleRaw = appearance.shellStyle or null;

  shellStyle =
    if shellStyleRaw == null then
      "quattro"
    else if builtins.elem shellStyleRaw [ "quattro" "islands" ] then
      shellStyleRaw
    else
      throw (
        "ryoku/settings.json: appearance.shellStyle must be \"quattro\", \"islands\" or null, got: "
        + builtins.toJSON shellStyleRaw
      );

  # -------------------------------------------------------------------------
  # Declarative apply subset — MUST stay in sync with modules that project
  # these keys. Adding a projection requires extending this attrset.
  #
  # Today:
  #   apps.flatpakDeclared → Debian: ryoku-flatpak-sync / pkg-helper (SYSTEM)
  #     (NixOS historically: modules/flatpak.nix → nix-flatpak)
  #   appearance.loginWallpaper → modules/desktop.nix SDDM (SYSTEM)
  #     (omitted from hash when null so default theme stays Applied)
  #   weather.location → home/dms.nix DMS session/settings (USER)
  #     (omitted from hash when null so the default stays Applied)
  #   appearance.shellStyle → modules/desktop.nix DMS build + home/dms.nix
  #     bar layout + home/hyprland.nix (SYSTEM; omitted when null = quattro)
  #
  # Not yet projected (intentionally omitted from hash):
  #   appearance.wallpaper (live DMS), appearance.wallpaperType /
  #   appearance.videoWallpaper (live mpvpaper unit),
  #   appearance.visualProfile / visualProfileAuto (live, DMS RyokuVisual), dynamicColors,
  #   display.monitors, …
  # -------------------------------------------------------------------------
  applySubset =
    {
      apps = {
        flatpakDeclared = flatpakDeclaredSorted;
      };
    }
    // lib.optionalAttrs (loginWallpaper != null || shellStyleRaw != null) {
      appearance =
        lib.optionalAttrs (loginWallpaper != null) { inherit loginWallpaper; }
        // lib.optionalAttrs (shellStyleRaw != null) { inherit shellStyle; };
    }
    // lib.optionalAttrs (weatherLocation != null) {
      weather = {
        location = weatherLocation;
      };
    };

  # Semantic hash: builtins.toJSON sorts attr keys; list order is normalized
  # above. Do NOT hash raw settings.json bytes (whitespace must not matter).
  settingsHash = builtins.hashString "sha256" (builtins.toJSON applySubset);

  # Inventory for GUI ApplyPlan (scope: "system" | "user").
  # Keep labels stable — Ryoku Settings may hardcode matching ids.
  applyInventory =
    [
      {
        id = "apps.flatpakDeclared";
        scope = "system";
        label = "Flatpak applications";
      }
    ]
    ++ lib.optionals (loginWallpaper != null) [
      {
        id = "appearance.loginWallpaper";
        scope = "system";
        label = "Login screen wallpaper";
      }
    ]
    ++ lib.optionals (weatherLocation != null) [
      {
        id = "weather.location";
        scope = "user";
        label = "Weather location";
      }
    ]
    ++ lib.optionals (shellStyleRaw != null) [
      {
        id = "appearance.shellStyle";
        scope = "system";
        label = "Shell style";
      }
    ];
in
{
  inherit settingsPath supportedSchemaVersion;
  settings = checked;

  inherit appearance apps desktop display weather hyprland;
  inherit get isSet orExisting;
  inherit flatpakDeclared flatpakDeclaredSorted;
  inherit applySubset settingsHash applyInventory;

  inherit loginWallpaper loginWallpaperPath;
  inherit weatherLocation;
  inherit shellStyle;

  # Canonical Ryoku pointer cursor (package = nixpkgs attribute name).
  # Not read from appearance.cursorTheme yet, so it stays out of applySubset.
  # Consumed by SDDM (modules/desktop.nix) and the session (home/cursor.nix).
  pointerCursor = {
    name = "Bibata-Modern-Ice";
    size = 24;
    package = "bibata-cursors";
  };

  # Convenience accessors (may be null).
  dynamicColors = appearance.dynamicColors or null;
  wallpaper = appearance.wallpaper or null;
  # null / "image" = static wallpaper; "video" = appearance.videoWallpaper.file.
  wallpaperType = appearance.wallpaperType or null;
  videoWallpaper = appearance.videoWallpaper or null;
  # null = "balanced"; read live by DMS (patches/dms/1.5.3/ryoku-visual-profile.patch).
  visualProfile = appearance.visualProfile or null;
  visualProfileAuto = appearance.visualProfileAuto or null;
  iconTheme = appearance.iconTheme or null;
  cursorTheme = appearance.cursorTheme or null;
  fontUi = appearance.fontUi or null;
  fontMono = appearance.fontMono or null;
  transparency = appearance.transparency or null;
  animations = appearance.animations or null;

  gapsIn = hyprland.gapsIn or null;
  gapsOut = hyprland.gapsOut or null;
  rounding = hyprland.rounding or null;
}
