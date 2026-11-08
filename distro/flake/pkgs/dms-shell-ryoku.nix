{
  dms-shell,
  patch,
  ryokuSettingsJson ? "/etc/ryoku/settings.json",
  ryokuShellStyle ? "quattro",
}:

# DankMaterialShell 1.5.3 + Ryoku visual patches (Quattro/Islands).
# Patches from Paulon34/ryoku-desktop (MIT) include DMS context lines
# (MIT — distro/LICENSES/MIT-DankMaterialShell.txt).
dms-shell.overrideAttrs (old: {
  pname = "dms-shell-ryoku";
  postInstall =
    (old.postInstall or "")
    + ''
      if [ "${old.version}" != "1.5.3" ]; then
        echo "error: Ryoku DMS patches are pinned to dms-shell 1.5.3 (got ${old.version})" >&2
        exit 1
      fi
      echo "Applying Ryoku DMS patches for ${old.version} (style=${ryokuShellStyle})..."
      chmod -R u+w "$out/share/quickshell/dms"
      patch_dir=${../patches/dms/1.5.3}
      for p in \
        ryoku-bar-islands.patch \
        ryoku-bar-polish.patch \
        ryoku-bar-media-island.patch \
        ryoku-bar-central-island.patch \
        ryoku-control-center.patch \
        ryoku-dankdash.patch \
        ryoku-shell-polish.patch \
        ryoku-notifications.patch \
        ryoku-tray-osd-blur.patch \
        ryoku-launcher.patch \
        ryoku-weather.patch \
        ryoku-bluetooth-empty-state.patch \
        ryoku-dankdash-polish.patch \
        ryoku-visual-profile.patch \
        ryoku-popout-depth.patch \
        ryoku-notifications-copy-dnd.patch \
        ryoku-quattro-foundation.patch \
        ryoku-quattro-bar.patch \
        ryoku-quattro-panels.patch \
        ryoku-quattro-launcher-menus.patch \
        ryoku-quattro-notifications-osd.patch \
        ryoku-quattro-lock.patch \
        ryoku-first-run.patch
      do
        ${patch}/bin/patch -p1 -d "$out/share/quickshell/dms" < "$patch_dir/$p"
      done
      if [ -f "$out/share/quickshell/dms/Common/RyokuVisual.qml" ]; then
        substituteInPlace "$out/share/quickshell/dms/Common/RyokuVisual.qml" \
          --replace-fail "@RYOKU_SETTINGS_JSON@" "${ryokuSettingsJson}" \
          --replace-fail "@RYOKU_SHELL_STYLE@" "${ryokuShellStyle}"
      fi
    '';
  meta = (old.meta or { }) // {
    description = "DankMaterialShell 1.5.3 with Ryoku Quattro/Islands patches";
  };
})
