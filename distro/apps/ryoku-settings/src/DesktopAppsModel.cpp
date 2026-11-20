#include "DesktopAppsModel.h"

#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>
#include <algorithm>

Q_LOGGING_CATEGORY(lcDesktopApps, "ryoku.settings.desktopapps")

namespace {

QStringList readPackageList(const QString &path)
{
    QStringList out;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return out;
    QTextStream in(&f);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        out.append(line);
    }
    return out;
}

QString prettyName(const QString &pkg)
{
    // Lightweight display names for common Ryoku APT apps.
    static const QHash<QString, QString> map{
        {QStringLiteral("firefox-esr"), QStringLiteral("Firefox ESR")},
        {QStringLiteral("kitty"), QStringLiteral("Kitty")},
        {QStringLiteral("thunar"), QStringLiteral("Thunar")},
        {QStringLiteral("file-roller"), QStringLiteral("File Roller")},
        {QStringLiteral("imv"), QStringLiteral("imv")},
        {QStringLiteral("mpv"), QStringLiteral("mpv")},
        {QStringLiteral("vlc"), QStringLiteral("VLC")},
        {QStringLiteral("gimp"), QStringLiteral("GIMP")},
        {QStringLiteral("libreoffice-gtk3"), QStringLiteral("LibreOffice")},
        {QStringLiteral("pavucontrol"), QStringLiteral("PulseAudio Volume Control")},
        {QStringLiteral("blueman"), QStringLiteral("Blueman")},
        {QStringLiteral("flatpak"), QStringLiteral("Flatpak")},
    };
    return map.value(pkg, pkg);
}

QString prettyIcon(const QString &pkg)
{
    static const QHash<QString, QString> map{
        {QStringLiteral("firefox-esr"), QStringLiteral("firefox-esr")},
        {QStringLiteral("kitty"), QStringLiteral("kitty")},
        {QStringLiteral("thunar"), QStringLiteral("org.xfce.thunar")},
        {QStringLiteral("file-roller"), QStringLiteral("org.gnome.FileRoller")},
        {QStringLiteral("imv"), QStringLiteral("image-x-generic")},
        {QStringLiteral("mpv"), QStringLiteral("mpv")},
        {QStringLiteral("vlc"), QStringLiteral("vlc")},
        {QStringLiteral("gimp"), QStringLiteral("gimp")},
        {QStringLiteral("libreoffice-gtk3"), QStringLiteral("libreoffice-main")},
        {QStringLiteral("pavucontrol"), QStringLiteral("multimedia-volume-control")},
        {QStringLiteral("blueman"), QStringLiteral("blueman")},
        {QStringLiteral("flatpak"), QStringLiteral("flatpak")},
    };
    return map.value(pkg, QStringLiteral("application-x-executable"));
}

// Curated APT apps shown in Settings (not the entire bootstrap base list).
const QStringList &curatedAptApps()
{
    static const QStringList apps{
        QStringLiteral("firefox-esr"),
        QStringLiteral("kitty"),
        QStringLiteral("thunar"),
        QStringLiteral("file-roller"),
        QStringLiteral("imv"),
        QStringLiteral("mpv"),
        QStringLiteral("vlc"),
        QStringLiteral("gimp"),
        QStringLiteral("libreoffice-gtk3"),
        QStringLiteral("pavucontrol"),
        QStringLiteral("blueman"),
        QStringLiteral("flatpak"),
    };
    return apps;
}

} // namespace

DesktopAppsModel::DesktopAppsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_helperPath = findPkgHelper();
}

int DesktopAppsModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QVariant DesktopAppsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const Row &row = m_rows.at(index.row());
    switch (role) {
    case AppIdRole:
        return row.appId;
    case NameRole:
        return row.name;
    case OriginRole:
        return static_cast<int>(row.origin);
    case OriginLabelRole:
        return originLabel(row.origin);
    case StatusRole:
        return static_cast<int>(row.status);
    case StatusLabelRole:
        switch (row.status) {
        case Installed:
            return QCoreApplication::translate("DesktopAppsModel", "Installed");
        case NotInstalled:
            return QCoreApplication::translate("DesktopAppsModel", "Not installed");
        case Unknown:
            return QCoreApplication::translate("DesktopAppsModel", "Unknown");
        }
        return {};
    case VersionRole:
        return row.version;
    case IconNameRole:
        return row.iconName;
    case CanInstallRole:
        return row.canInstall && helperAvailable();
    case CanUpdateRole:
        return row.canUpdate && helperAvailable();
    case CanRemoveRole:
        return row.canRemove && helperAvailable();
    default:
        return {};
    }
}

QHash<int, QByteArray> DesktopAppsModel::roleNames() const
{
    return {
        {AppIdRole, "appId"},
        {NameRole, "name"},
        {OriginRole, "origin"},
        {OriginLabelRole, "originLabel"},
        {StatusRole, "status"},
        {StatusLabelRole, "statusLabel"},
        {VersionRole, "version"},
        {IconNameRole, "iconName"},
        {CanInstallRole, "canInstall"},
        {CanUpdateRole, "canUpdate"},
        {CanRemoveRole, "canRemove"},
    };
}

QString DesktopAppsModel::originLabel(Origin o)
{
    switch (o) {
    case Apt:
        return QStringLiteral("APT");
    case Flatpak:
        return QStringLiteral("Flatpak");
    case Nix:
        return QStringLiteral("Nix");
    }
    return {};
}

QString DesktopAppsModel::findPkgHelper()
{
    const QStringList candidates{
        QStringLiteral("/usr/local/libexec/ryoku-pkg-helper"),
        QStringLiteral("/etc/ryoku/pkg-helper"),
    };
    for (const QString &c : candidates) {
        if (c.endsWith(QStringLiteral("pkg-helper")) && !c.contains(QLatin1String("libexec"))) {
            QFile f(c);
            if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
                const QString path = QString::fromUtf8(f.readAll()).trimmed();
                if (QFileInfo(path).isExecutable())
                    return path;
            }
            continue;
        }
        if (QFileInfo(c).isExecutable())
            return c;
    }
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("ryoku-pkg-helper"));
    if (!fromPath.isEmpty())
        return fromPath;
    return {};
}

void DesktopAppsModel::setRepoPath(const QString &path)
{
    if (m_repoPath == path)
        return;
    m_repoPath = path;
    emit repoPathChanged();
    rebuild();
}

void DesktopAppsModel::refresh()
{
    m_helperPath = findPkgHelper();
    rebuild();
}

void DesktopAppsModel::retranslateUi()
{
    emit changed();
}

void DesktopAppsModel::rebuild()
{
    beginResetModel();
    m_rows.clear();
    m_error.clear();
    loadAptCatalog();
    loadFlatpakRows();
    loadNixHints();
    std::sort(m_rows.begin(), m_rows.end(), [](const Row &a, const Row &b) {
        if (a.origin != b.origin)
            return static_cast<int>(a.origin) < static_cast<int>(b.origin);
        return a.name.toLower() < b.name.toLower();
    });
    endResetModel();
    emit changed();
}

void DesktopAppsModel::loadAptCatalog()
{
    QSet<QString> allow;
    if (!m_repoPath.isEmpty()) {
        const QStringList lists{
            QStringLiteral("distro/apt/packages-base.txt"),
            QStringLiteral("distro/apt/packages-full.txt"),
            QStringLiteral("distro/apt/packages-hyprland.txt"),
        };
        for (const QString &rel : lists) {
            for (const QString &pkg : readPackageList(m_repoPath + QLatin1Char('/') + rel))
                allow.insert(pkg);
        }
    }

    for (const QString &pkg : curatedAptApps()) {
        if (!allow.isEmpty() && !allow.contains(pkg))
            continue;
        Row row;
        row.appId = pkg;
        row.name = prettyName(pkg);
        row.origin = Apt;
        row.iconName = prettyIcon(pkg);

        QProcess proc;
        proc.start(QStringLiteral("dpkg-query"),
                   {QStringLiteral("-W"), QStringLiteral("-f=${Version}"), pkg});
        if (proc.waitForFinished(3000) && proc.exitCode() == 0) {
            row.version = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
            row.status = row.version.isEmpty() ? NotInstalled : Installed;
        } else {
            row.status = NotInstalled;
            row.version.clear();
        }
        row.canInstall = row.status == NotInstalled;
        row.canUpdate = row.status == Installed;
        row.canRemove = row.status == Installed
            && pkg != QLatin1String("flatpak"); // keep plumbing
        m_rows.append(row);
    }
}

void DesktopAppsModel::loadFlatpakRows()
{
    const QString flatpak = QStandardPaths::findExecutable(QStringLiteral("flatpak"));
    if (flatpak.isEmpty())
        return;

    // Declared IDs from profile manifests when repo is known.
    QSet<QString> declared;
    if (!m_repoPath.isEmpty()) {
        for (const QString &rel : {QStringLiteral("distro/flatpak/apps-minimal.txt"),
                                   QStringLiteral("distro/flatpak/apps-full.txt")}) {
            for (const QString &id : readPackageList(m_repoPath + QLatin1Char('/') + rel))
                declared.insert(id);
        }
    }

    QProcess proc;
    proc.start(flatpak,
               {QStringLiteral("list"), QStringLiteral("--app"),
                QStringLiteral("--columns=application,name,version")});
    QHash<QString, QPair<QString, QString>> installed;
    if (proc.waitForFinished(8000) && proc.exitCode() == 0) {
        const QString text = QString::fromUtf8(proc.readAllStandardOutput());
        for (const QString &raw : text.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList cols = raw.split(QLatin1Char('\t'));
            if (cols.isEmpty())
                continue;
            const QString id = cols.at(0).trimmed();
            if (id.isEmpty() || id == QLatin1String("Application"))
                continue;
            const QString name = cols.size() > 1 ? cols.at(1).trimmed() : id;
            const QString ver = cols.size() > 2 ? cols.at(2).trimmed() : QString();
            installed.insert(id, {name, ver});
        }
    }

    QSet<QString> seen;
    for (const QString &id : declared) {
        Row row;
        row.appId = id;
        row.origin = Flatpak;
        row.iconName = QStringLiteral("flatpak");
        if (installed.contains(id)) {
            row.name = installed.value(id).first;
            row.version = installed.value(id).second;
            row.status = Installed;
            row.canUpdate = true;
            row.canRemove = true;
            row.canInstall = false;
        } else {
            row.name = id;
            row.status = NotInstalled;
            row.canInstall = true;
        }
        m_rows.append(row);
        seen.insert(id);
    }

    // Local (undeclared) Flatpaks — show with origin, no install button.
    for (auto it = installed.begin(); it != installed.end(); ++it) {
        if (seen.contains(it.key()))
            continue;
        Row row;
        row.appId = it.key();
        row.name = it.value().first;
        row.version = it.value().second;
        row.origin = Flatpak;
        row.iconName = QStringLiteral("flatpak");
        row.status = Installed;
        row.canRemove = true;
        row.canUpdate = true;
        m_rows.append(row);
    }
}

void DesktopAppsModel::loadNixHints()
{
    // Read-only hints for key Nix-provided desktop tools (no install via APT helper).
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    const QStringList hints{
        QStringLiteral("dms"),
        QStringLiteral("matugen"),
        QStringLiteral("ryoku-settings"),
    };
    for (const QString &bin : hints) {
        QString path = QStandardPaths::findExecutable(bin);
        if (path.isEmpty()) {
            const QStringList cands{
                home + QStringLiteral("/.local/state/nix/profiles/home-manager/home-path/bin/") + bin,
                home + QStringLiteral("/.nix-profile/bin/") + bin,
            };
            for (const QString &c : cands) {
                if (QFileInfo(c).isExecutable()) {
                    path = c;
                    break;
                }
            }
        }
        if (path.isEmpty())
            continue;
        Row row;
        row.appId = bin;
        row.name = bin;
        row.origin = Nix;
        row.iconName = QStringLiteral("application-x-executable");
        row.status = Installed;
        row.version = QFileInfo(path).absoluteFilePath();
        // Never allow APT/Flatpak helper to mutate Nix packages.
        row.canInstall = false;
        row.canUpdate = false;
        row.canRemove = false;
        m_rows.append(row);
    }
}

bool DesktopAppsModel::runPkexecHelper(const QStringList &helperArgs, QString *errorOut)
{
    if (m_helperPath.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("ryoku-pkg-helper not installed");
        return false;
    }
    const QString pkexec = QFileInfo(QStringLiteral("/usr/bin/pkexec")).isExecutable()
        ? QStringLiteral("/usr/bin/pkexec")
        : QStandardPaths::findExecutable(QStringLiteral("pkexec"));
    if (pkexec.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("pkexec not found");
        return false;
    }

    QStringList argv = helperArgs;
    argv.prepend(m_helperPath);

    QProcess proc;
    proc.start(pkexec, argv);
    if (!proc.waitForFinished(600000)) {
        if (errorOut)
            *errorOut = QStringLiteral("pkexec timed out");
        return false;
    }
    if (proc.exitCode() != 0) {
        if (errorOut) {
            *errorOut = QString::fromUtf8(proc.readAllStandardError()).trimmed();
            if (errorOut->isEmpty())
                *errorOut = QStringLiteral("helper exit %1").arg(proc.exitCode());
        }
        return false;
    }
    return true;
}

bool DesktopAppsModel::installApp(const QString &appId, int origin)
{
    QString err;
    m_busy = true;
    emit busyChanged();
    bool ok = false;
    if (origin == Apt)
        ok = runPkexecHelper({QStringLiteral("apt-install"), appId}, &err);
    else if (origin == Flatpak)
        ok = runPkexecHelper({QStringLiteral("flatpak-install"), appId}, &err);
    else
        err = QStringLiteral("Nix packages are managed by Home Manager Apply");
    m_busy = false;
    emit busyChanged();
    if (!ok) {
        m_error = err;
        emit changed();
        emit operationFinished(false, err);
        return false;
    }
    refresh();
    emit operationFinished(true, QStringLiteral("installed %1").arg(appId));
    return true;
}

bool DesktopAppsModel::updateApp(const QString &appId, int origin)
{
    QString err;
    m_busy = true;
    emit busyChanged();
    bool ok = false;
    if (origin == Apt)
        ok = runPkexecHelper({QStringLiteral("apt-install"), appId}, &err); // apt install = upgrade
    else if (origin == Flatpak)
        ok = runPkexecHelper({QStringLiteral("flatpak-update"), appId}, &err);
    else
        err = QStringLiteral("Nix packages are managed by Home Manager Apply");
    m_busy = false;
    emit busyChanged();
    if (!ok) {
        m_error = err;
        emit changed();
        emit operationFinished(false, err);
        return false;
    }
    refresh();
    emit operationFinished(true, QStringLiteral("updated %1").arg(appId));
    return true;
}

bool DesktopAppsModel::removeApp(const QString &appId, int origin)
{
    QString err;
    m_busy = true;
    emit busyChanged();
    bool ok = false;
    if (origin == Apt)
        ok = runPkexecHelper({QStringLiteral("apt-remove"), appId}, &err);
    else if (origin == Flatpak)
        ok = runPkexecHelper({QStringLiteral("flatpak-remove"), appId}, &err);
    else
        err = QStringLiteral("Nix packages are managed by Home Manager Apply");
    m_busy = false;
    emit busyChanged();
    if (!ok) {
        m_error = err;
        emit changed();
        emit operationFinished(false, err);
        return false;
    }
    refresh();
    emit operationFinished(true, QStringLiteral("removed %1").arg(appId));
    return true;
}
