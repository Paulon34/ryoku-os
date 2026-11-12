#include "WallpaperGalleryModel.h"
#include "SettingsStore.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QLoggingCategory>
#include <QProcess>
#include <QUrl>
#include <QtGlobal>

Q_LOGGING_CATEGORY(lcWallGallery, "ryoku.settings.wallpaper.gallery")

WallpaperGalleryModel::WallpaperGalleryModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

WallpaperGalleryModel::WallpaperGalleryModel(MediaKind kind, QObject *parent)
    : QAbstractListModel(parent)
    , m_kind(kind)
{
}

void WallpaperGalleryModel::setRepoPath(const QString &repoPath)
{
    m_repoPath = repoPath;
    reload();
}

QString WallpaperGalleryModel::resolveGalleryPath(const QString &repoPath)
{
    const QString homeShare = QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
                                  .filePath(QStringLiteral(".local/share/wallpapers"));
    if (QDir(homeShare).exists())
        return QFileInfo(homeShare).absoluteFilePath();

    if (!repoPath.isEmpty()) {
        const QStringList candidates{
            QDir(repoPath).filePath(QStringLiteral("assets/wallpapers")),
            QDir(repoPath).filePath(QStringLiteral("distro/assets/wallpapers")),
        };
        for (const QString &repoAssets : candidates) {
            if (QDir(repoAssets).exists())
                return QFileInfo(repoAssets).absoluteFilePath();
        }
    }
    return homeShare;
}

QString WallpaperGalleryModel::resolvePrivateGalleryPath()
{
    // XDG data home — machine-local imports; never commit to the public repo.
    const QString xdg = qEnvironmentVariable("XDG_DATA_HOME");
    const QString base = xdg.isEmpty()
        ? QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
              .filePath(QStringLiteral(".local/share"))
        : xdg;
    return QDir(base).filePath(QStringLiteral("ryoku/wallpapers-private"));
}

QString WallpaperGalleryModel::findVideoHelper()
{
    const QString name = QStringLiteral("ryoku-video-wallpaper");
    const QString fromPath = QStandardPaths::findExecutable(name);
    if (!fromPath.isEmpty())
        return fromPath;

    // Home Manager user profile when PATH is minimal (e.g. nix run).
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    const QStringList candidates{
        QStringLiteral("/etc/profiles/per-user/%1/bin/%2").arg(qEnvironmentVariable("USER"), name),
        QDir(home).filePath(QStringLiteral(".nix-profile/bin/%1").arg(name)),
    };
    for (const QString &c : candidates) {
        const QFileInfo fi(c);
        if (fi.exists() && fi.isExecutable())
            return fi.absoluteFilePath();
    }
    return {};
}

bool WallpaperGalleryModel::isValidId(const QString &id) const
{
    return isVideoGallery() ? SettingsStore::isValidVideoWallpaperId(id)
                            : SettingsStore::isValidWallpaperId(id);
}

void WallpaperGalleryModel::appendFromDir(const QString &dirPath, const QStringList &nameFilters)
{
    QDir dir(dirPath);
    if (!dir.exists())
        return;
    const QFileInfoList infos = dir.entryInfoList(nameFilters, QDir::Files | QDir::Readable, QDir::Name);
    for (const QFileInfo &fi : infos) {
        const QString name = fi.fileName();
        if (!isValidId(name))
            continue;
        // Public first; private adds only new basenames (no silent overwrite of CC0 set).
        if (m_absById.contains(name))
            continue;
        m_absById.insert(name, fi.absoluteFilePath());
        m_files.append(name);
    }
}

void WallpaperGalleryModel::reload()
{
    beginResetModel();
    m_files.clear();
    m_absById.clear();
    m_posterQueue.clear();
    if (m_posterProc && m_posterProc->state() != QProcess::NotRunning)
        m_posterProc->kill();
    m_galleryPath = resolveGalleryPath(m_repoPath);

    const QStringList nameFilters = isVideoGallery()
        ? QStringList{QStringLiteral("*.mp4"), QStringLiteral("*.webm"),
                      QStringLiteral("*.mkv"), QStringLiteral("*.mov"),
                      QStringLiteral("*.MP4"), QStringLiteral("*.WEBM"),
                      QStringLiteral("*.MKV"), QStringLiteral("*.MOV")}
        : QStringList{QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"),
                      QStringLiteral("*.png"), QStringLiteral("*.webp"),
                      QStringLiteral("*.JPG"), QStringLiteral("*.JPEG"),
                      QStringLiteral("*.PNG"), QStringLiteral("*.WEBP")};

    appendFromDir(m_galleryPath, nameFilters);
    if (!isVideoGallery())
        appendFromDir(resolvePrivateGalleryPath(), nameFilters);

    if (m_files.isEmpty())
        qWarning(lcWallGallery) << "gallery empty — public:" << m_galleryPath
                                << "private:" << resolvePrivateGalleryPath();

    qInfo(lcWallGallery) << "gallery" << m_galleryPath << (isVideoGallery() ? "videos" : "images")
                         << "count" << m_files.size();
    endResetModel();
    emit countChanged();

    if (isVideoGallery()) {
        m_posterQueue = m_files;
        startNextPoster();
    }
}

// Sequential, one QProcess at a time; cached posters return without ffmpeg.
void WallpaperGalleryModel::startNextPoster()
{
    if (m_posterProc && m_posterProc->state() != QProcess::NotRunning)
        return;
    if (m_posterQueue.isEmpty())
        return;

    const QString helper = findVideoHelper();
    if (helper.isEmpty()) {
        qWarning(lcWallGallery) << "ryoku-video-wallpaper not found; video thumbnails unavailable";
        m_posterQueue.clear();
        return;
    }

    if (!m_posterProc) {
        m_posterProc = new QProcess(this);
        m_posterProc->setProcessChannelMode(QProcess::SeparateChannels);
        connect(m_posterProc, &QProcess::finished, this,
                [this](int exitCode, QProcess::ExitStatus status) {
                    const QString id = m_posterPending;
                    m_posterPending.clear();
                    const QString out = QString::fromUtf8(m_posterProc->readAllStandardOutput()).trimmed();
                    const QString poster = out.section(QLatin1Char('\n'), -1).trimmed();
                    if (status == QProcess::NormalExit && exitCode == 0 && QFileInfo(poster).isFile()) {
                        m_posters.insert(id, poster);
                        const int row = m_files.indexOf(id);
                        if (row >= 0) {
                            const QModelIndex idx = index(row);
                            emit dataChanged(idx, idx, {PosterUrlRole});
                        }
                        ++m_posterRevision;
                        emit postersChanged();
                    } else {
                        qWarning(lcWallGallery) << "poster failed for" << id
                                                << QString::fromUtf8(m_posterProc->readAllStandardError()).trimmed();
                    }
                    startNextPoster();
                });
    }

    m_posterPending = m_posterQueue.takeFirst();
    m_posterProc->start(helper, {QStringLiteral("poster"), QDir(m_galleryPath).filePath(m_posterPending)});
}

int WallpaperGalleryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_files.size();
}

QVariant WallpaperGalleryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_files.size())
        return {};

    const QString name = m_files.at(index.row());
    const QString abs = m_absById.value(name, QDir(m_galleryPath).filePath(name));

    switch (role) {
    case FileNameRole:
        return name;
    case AbsolutePathRole:
        return abs;
    case UrlRole:
        return QUrl::fromLocalFile(abs);
    case IsVideoRole:
        return isVideoGallery();
    case PosterUrlRole:
        return posterUrlForId(name);
    default:
        return {};
    }
}

QHash<int, QByteArray> WallpaperGalleryModel::roleNames() const
{
    return {
        {FileNameRole, "fileName"},
        {AbsolutePathRole, "absolutePath"},
        {UrlRole, "url"},
        {IsVideoRole, "isVideo"},
        {PosterUrlRole, "posterUrl"},
    };
}

QString WallpaperGalleryModel::absolutePathForId(const QString &id) const
{
    if (!isValidId(id))
        return {};
    // Prefer merged map (public + private). Basename-only id — no traversal.
    QString candidate = m_absById.value(id);
    if (candidate.isEmpty())
        candidate = QDir(m_galleryPath).filePath(id);
    const QFileInfo fi(candidate);
    // exists/isFile follow symlinks to a regular file (HM installs store symlinks).
    if (!fi.exists() || !fi.isFile())
        return {};
    if (fi.fileName() != id)
        return {};
    // Pass the gallery entry path (not the nix-store canonical target) to DMS —
    // same form as scripts/change-wallpaper.sh. Never bake machine-specific
    // absolute paths into settings.json — only the basename id is persisted.
    return fi.absoluteFilePath();
}

QUrl WallpaperGalleryModel::urlForId(const QString &id) const
{
    const QString abs = absolutePathForId(id);
    if (abs.isEmpty())
        return {};
    return QUrl::fromLocalFile(abs);
}

QUrl WallpaperGalleryModel::posterUrlForId(const QString &id) const
{
    if (!isVideoGallery())
        return urlForId(id);
    const QString poster = m_posters.value(id);
    if (poster.isEmpty())
        return {};
    return QUrl::fromLocalFile(poster);
}
