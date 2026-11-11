#pragma once

#include <QString>

namespace Ryoku {

// Canonical desktop / portal / Wayland identity (must match installed .desktop).
inline constexpr const char *kAppId = "org.ryoku.Settings";
inline constexpr const char *kDesktopFileName = "org.ryoku.Settings.desktop";
inline constexpr const char *kAppDisplayName = "Ryoku Settings";
inline constexpr const char *kOrganizationName = "Ryoku";
inline constexpr const char *kOrganizationDomain = "ryoku.local";
// Theme fallback name until final brand art is approved; package installs
// hicolor icons under this canonical FreeDesktop name.
inline constexpr const char *kIconName = "org.ryoku.Settings";

// Central repo path resolution (no scattered home paths in callers).
// Order: RYOKU_REPO_PATH env → compile-time default (Nix) → $HOME/ryoku, $HOME/ryoku-desktop
// Never uses process cwd / ".".
QString resolveRepoPath();

bool looksLikeRyokuRepo(const QString &path);

} // namespace Ryoku
