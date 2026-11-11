#include "RepoPath.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

#include <cstdlib>

namespace Ryoku {

bool looksLikeRyokuRepo(const QString &path)
{
    if (path.isEmpty())
        return false;
    const QDir dir(path);
    // NixOS / ryoku-desktop layout OR Debian Modular (ryoku-os) layout.
    const bool hasSettings = dir.exists(QStringLiteral("ryoku/settings.json"))
        || dir.exists(QStringLiteral("distro/ryoku/settings.json"));
    const bool hasFlake = dir.exists(QStringLiteral("flake.nix"))
        || dir.exists(QStringLiteral("distro/flake/flake.nix"));
    return hasSettings && hasFlake;
}

QString resolveRepoPath()
{
    // Never use process cwd / "." — launcher starts with arbitrary working directory.
    if (const char *env = std::getenv("RYOKU_REPO_PATH")) {
        const QString fromEnv = QString::fromLocal8Bit(env).trimmed();
        if (looksLikeRyokuRepo(fromEnv))
            return QFileInfo(fromEnv).absoluteFilePath();
    }

#ifdef RYOKU_REPO_PATH_DEFAULT
    {
        const QString baked = QString::fromUtf8(RYOKU_REPO_PATH_DEFAULT).trimmed();
        if (looksLikeRyokuRepo(baked))
            return QFileInfo(baked).absoluteFilePath();
    }
#endif

    // Where the README and ryoku-bootstrap put a checkout.
    const QDir home(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
    for (const QString &name :
         {QStringLiteral("ryoku-os"), QStringLiteral("ryoku-os-visual"), QStringLiteral("ryoku"),
          QStringLiteral("ryoku-desktop")}) {
        const QString candidate = home.filePath(name);
        if (looksLikeRyokuRepo(candidate))
            return QFileInfo(candidate).absoluteFilePath();
    }

    return QString();
}

} // namespace Ryoku
