#include "WallpaperGalleryModel.h"
#include "SettingsStore.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <QtGlobal>

Q_LOGGING_CATEGORY(lcWallGallery, "ryoku.settings.wallpaper.gallery")

namespace {

QStringList imageFilters()
{
    return {
        QStringLiteral("*.jpg"),  QStringLiteral("*.jpeg"), QStringLiteral("*.png"),
        QStringLiteral("*.webp"), QStringLiteral("*.JPG"),  QStringLiteral("*.JPEG"),
        QStringLiteral("*.PNG"),  QStringLiteral("*.WEBP"),
    };
}

QStringList videoFilters()
{
    return {
        QStringLiteral("*.mp4"),  QStringLiteral("*.webm"), QStringLiteral("*.mkv"),
        QStringLiteral("*.mov"),  QStringLiteral("*.MP4"),  QStringLiteral("*.WEBM"),
        QStringLiteral("*.MKV"),  QStringLiteral("*.MOV"),
    };
}

} // namespace

WallpaperGalleryModel::WallpaperGalleryModel(QObject *parent)
    : WallpaperGalleryModel(MediaKind::Images, parent)
{
}

WallpaperGalleryModel::WallpaperGalleryModel(MediaKind kind, QObject *parent)
    : QAbstractListModel(parent)
    , m_kind(kind)
{
    m_reloadDebounce = new QTimer(this);
    m_reloadDebounce->setSingleShot(true);
    m_reloadDebounce->setInterval(350);
    connect(m_reloadDebounce, &QTimer::timeout, this, [this]() {
        m_reloadQueued = false;
        reload();
    });
    loadExtraFolders();
}

WallpaperGalleryModel::~WallpaperGalleryModel()
{
    // Tear down poster FFmpeg helper before QProcess dtor (avoids
    // "QProcess: Destroyed while process is still running" on UI fail/close).
    m_posterQueue.clear();
    m_posterPending.clear();
    if (m_posterProc) {
        m_posterProc->disconnect();
        if (m_posterProc->state() != QProcess::NotRunning) {
            m_posterProc->kill();
            m_posterProc->waitForFinished(2000);
        }
    }
}

void WallpaperGalleryModel::setRepoPath(const QString &repoPath)
{
    m_repoPath = repoPath;
    reload();
}

void WallpaperGalleryModel::setFilter(const QString &filter)
{
    const QString normalized = filter.trimmed().toLower();
    const QStringList allowed{QStringLiteral("all"), QStringLiteral("images"),
                              QStringLiteral("videos"), QStringLiteral("private"),
                              QStringLiteral("repository")};
    const QString next = allowed.contains(normalized) ? normalized : QStringLiteral("all");
    if (next == m_filter)
        return;
    m_filter = next;
    rebuildVisible();
    emit filterChanged();
}

void WallpaperGalleryModel::setLastError(const QString &err)
{
    if (m_lastError == err)
        return;
    m_lastError = err;
    emit lastErrorChanged();
}

void WallpaperGalleryModel::setLastImportSummary(const QString &summary)
{
    if (m_lastImportSummary == summary)
        return;
    m_lastImportSummary = summary;
    emit lastImportSummaryChanged();
}

void WallpaperGalleryModel::setImportBusy(bool busy)
{
    if (m_importBusy == busy)
        return;
    m_importBusy = busy;
    emit importBusyChanged();
}

void WallpaperGalleryModel::setImportProgress(int progress)
{
    const int clamped = qBound(0, progress, 100);
    if (m_importProgress == clamped)
        return;
    m_importProgress = clamped;
    emit importProgressChanged();
}

QUrl WallpaperGalleryModel::coerceToUrl(const QVariant &value)
{
    if (value.canConvert<QUrl>()) {
        const QUrl u = value.toUrl();
        if (!u.isEmpty())
            return u;
    }
    const QString s = value.toString().trimmed();
    if (s.isEmpty())
        return {};
    // QML sometimes hands FileDialog entries as plain strings ("file:///…").
    const QUrl asUrl = QUrl::fromUserInput(s, QString(), QUrl::AssumeLocalFile);
    if (asUrl.isValid())
        return asUrl;
    return QUrl::fromLocalFile(s);
}

QString WallpaperGalleryModel::mediaKindForFileName(const QString &fileName)
{
    if (SettingsStore::isValidWallpaperId(fileName))
        return QStringLiteral("image");
    if (SettingsStore::isValidVideoWallpaperId(fileName))
        return QStringLiteral("video");
    return {};
}

QString WallpaperGalleryModel::localPathFromUrl(const QUrl &url) const
{
    if (!url.isValid() || url.isEmpty())
        return {};
    if (!url.isLocalFile())
        return {};
    // QUrl::toLocalFile decodes percent-encoding (%20, UTF-8, # fragments stripped
    // from path correctly via isLocalFile path). Never strip "file://" manually.
    const QString path = url.toLocalFile();
    if (path.isEmpty())
        return {};
    const QFileInfo fi(path);
    if (!fi.exists())
        return {};
    if (!fi.isReadable())
        return {};
    return fi.absoluteFilePath();
}

QStringList WallpaperGalleryModel::localPathsFromUrls(const QVariantList &urls) const
{
    QStringList out;
    out.reserve(urls.size());
    for (const QVariant &v : urls) {
        const QString path = localPathFromUrl(coerceToUrl(v));
        if (!path.isEmpty())
            out.append(path);
    }
    return out;
}

QString WallpaperGalleryModel::formatByteSize(qint64 bytes) const
{
    if (bytes < 0)
        return {};
    constexpr qint64 KiB = 1024;
    constexpr qint64 MiB = 1024 * KiB;
    if (bytes < KiB)
        return QCoreApplication::translate("WallpaperGalleryModel", "%1 B").arg(bytes);
    if (bytes < MiB) {
        return QCoreApplication::translate("WallpaperGalleryModel", "%1 KiB")
            .arg(QString::number(bytes / double(KiB), 'f', bytes < 10 * KiB ? 1 : 0));
    }
    return QCoreApplication::translate("WallpaperGalleryModel", "%1 MiB")
        .arg(QString::number(bytes / double(MiB), 'f', bytes < 10 * MiB ? 1 : 0));
}

void WallpaperGalleryModel::clearImportHighlight()
{
    if (m_lastImportedIds.isEmpty())
        return;
    m_lastImportedIds.clear();
    emit lastImportedIdsChanged();
}

bool WallpaperGalleryModel::isRecentlyImported(const QString &id) const
{
    return m_lastImportedIds.contains(id);
}

QString WallpaperGalleryModel::resolveInstalledGalleryPath()
{
    const QString homeShare = QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
                                  .filePath(QStringLiteral(".local/share/wallpapers"));
    return QFileInfo(homeShare).absoluteFilePath();
}

QString WallpaperGalleryModel::resolveRepoGalleryPath(const QString &repoPath)
{
    if (repoPath.isEmpty())
        return {};
    const QStringList candidates{
        QDir(repoPath).filePath(QStringLiteral("distro/assets/wallpapers")),
        QDir(repoPath).filePath(QStringLiteral("assets/wallpapers")),
    };
    for (const QString &repoAssets : candidates) {
        if (QDir(repoAssets).exists())
            return QFileInfo(repoAssets).absoluteFilePath();
    }
    // Prefer the Debian Modular layout even when the directory is not created yet.
    return QFileInfo(candidates.constFirst()).absoluteFilePath();
}

QString WallpaperGalleryModel::resolveGalleryPath(const QString &repoPath)
{
    // Compat helper: prefer installed share when present, else first available root.
    const QStringList roots = resolveGalleryRoots(repoPath);
    if (!roots.isEmpty())
        return roots.constFirst();
    return resolveInstalledGalleryPath();
}

QStringList WallpaperGalleryModel::resolveGalleryRoots(const QString &repoPath,
                                                       const QStringList &extraFolders)
{
    QStringList roots;
    QSet<QString> seen;

    const auto add = [&](const QString &path) {
        if (path.isEmpty())
            return;
        const QString abs = QFileInfo(path).absoluteFilePath();
        if (seen.contains(abs))
            return;
        if (!QDir(abs).exists())
            return;
        seen.insert(abs);
        roots.append(abs);
    };

    // Order: installed HM share → repo checkout → private → extras.
    add(resolveInstalledGalleryPath());
    add(resolveRepoGalleryPath(repoPath));
    add(resolvePrivateGalleryPath());
    for (const QString &extra : extraFolders)
        add(extra);

    return roots;
}

QString WallpaperGalleryModel::resolvePrivateGalleryPath()
{
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

    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    const QStringList candidates{
        QDir(home).filePath(QStringLiteral(".local/bin/%1").arg(name)),
        QDir(home).filePath(
            QStringLiteral(".local/state/nix/profiles/home-manager/home-path/bin/%1").arg(name)),
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

bool WallpaperGalleryModel::pathLooksLikeNixStore(const QString &path)
{
    if (path.isEmpty())
        return false;
    const QString canon = QFileInfo(path).canonicalFilePath();
    const QString probe = canon.isEmpty() ? QFileInfo(path).absoluteFilePath() : canon;
    return probe.startsWith(QStringLiteral("/nix/store/"));
}

QString WallpaperGalleryModel::uniqueDestName(const QString &dirPath, const QString &preferredName)
{
    const QString baseName = QFileInfo(preferredName).fileName();
    if (baseName.isEmpty())
        return {};
    QDir dir(dirPath);
    if (!dir.exists(baseName))
        return baseName;

    const QFileInfo fi(baseName);
    const QString stem = fi.completeBaseName();
    const QString ext = fi.suffix();
    for (int i = 1; i < 10000; ++i) {
        const QString candidate = ext.isEmpty()
            ? QStringLiteral("%1 (%2)").arg(stem).arg(i)
            : QStringLiteral("%1 (%2).%3").arg(stem).arg(i).arg(ext);
        if (!dir.exists(candidate))
            return candidate;
    }
    return {};
}

QString WallpaperGalleryModel::ensureWritableCopy(const QString &sourceAbs, const QString &destDir,
                                                    const QString &preferredName, QString *errorOut)
{
    const auto fail = [&](const QString &msg) -> QString {
        if (errorOut)
            *errorOut = msg;
        return {};
    };

    const QFileInfo src(sourceAbs);
    if (!src.exists() || !src.isFile())
        return fail(QStringLiteral("source missing"));

    if (!QDir().mkpath(destDir))
        return fail(QStringLiteral("cannot create destination directory"));

    // Never write into the Nix store itself.
    if (pathLooksLikeNixStore(destDir))
        return fail(QStringLiteral("refusing to write into Nix store"));

    const QString destName = uniqueDestName(destDir, preferredName.isEmpty() ? src.fileName()
                                                                            : preferredName);
    if (destName.isEmpty())
        return fail(QStringLiteral("could not allocate unique name"));

    const QString destAbs = QDir(destDir).filePath(destName);

    // If source is already a regular writable file in destDir, reuse it.
    if (QFileInfo(sourceAbs).absoluteFilePath() == QFileInfo(destAbs).absoluteFilePath()
        && !src.isSymLink() && src.isWritable())
        return destAbs;

    QFile::remove(destAbs);
    // Copy file contents — follows symlink to store file but writes a real file out.
    if (!QFile::copy(src.absoluteFilePath(), destAbs))
        return fail(QStringLiteral("copy failed"));

    QFile dest(destAbs);
    dest.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup
                        | QFileDevice::ReadOther);
    return destAbs;
}

bool WallpaperGalleryModel::isValidId(const QString &id) const
{
    return isVideoGallery() ? SettingsStore::isValidVideoWallpaperId(id)
                            : SettingsStore::isValidWallpaperId(id);
}

QString WallpaperGalleryModel::originKey(Origin o)
{
    switch (o) {
    case Origin::Installed:
        return QStringLiteral("installed");
    case Origin::Repo:
        return QStringLiteral("repository");
    case Origin::Private:
        return QStringLiteral("private");
    case Origin::Extra:
        return QStringLiteral("extra");
    }
    return QStringLiteral("installed");
}

QString WallpaperGalleryModel::originLabel(Origin o)
{
    switch (o) {
    case Origin::Installed:
        return QCoreApplication::translate("WallpaperGalleryModel", "Installed");
    case Origin::Repo:
        return QCoreApplication::translate("WallpaperGalleryModel", "Repository");
    case Origin::Private:
        return QCoreApplication::translate("WallpaperGalleryModel", "Private");
    case Origin::Extra:
        return QCoreApplication::translate("WallpaperGalleryModel", "Folder");
    }
    return {};
}

bool WallpaperGalleryModel::passesFilter(const Entry &e, const QString &filter)
{
    if (filter == QLatin1String("images"))
        return !e.isVideo;
    if (filter == QLatin1String("videos"))
        return e.isVideo;
    if (filter == QLatin1String("private"))
        return e.origin == Origin::Private;
    if (filter == QLatin1String("repository"))
        return e.origin == Origin::Repo || e.origin == Origin::Installed;
    return true; // all
}

void WallpaperGalleryModel::appendFromDir(const QString &dirPath, Origin origin,
                                          const QStringList &nameFilters)
{
    QDir dir(dirPath);
    if (!dir.exists())
        return;
    const QFileInfoList infos =
        dir.entryInfoList(nameFilters, QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                          QDir::Name);
    for (const QFileInfo &fi : infos) {
        const QString name = fi.fileName();
        // Accept gallery media even when a stricter SettingsStore id rejects it —
        // invalid entries stay visible but cannot be applied until renamed.
        const bool validImage = SettingsStore::isValidWallpaperId(name);
        const bool validVideo = SettingsStore::isValidVideoWallpaperId(name);
        const bool isVideo = validVideo
            || (!validImage
                && name.contains(QRegularExpression(QStringLiteral("\\.(mp4|webm|mkv|mov)$"),
                                                    QRegularExpression::CaseInsensitiveOption)));
        if (m_kind == MediaKind::Images && isVideo)
            continue;
        if (m_kind == MediaKind::Videos && !isVideo)
            continue;
        if (!validImage && !validVideo)
            continue; // still require basename-safe id with known extension
        if (m_absById.contains(name))
            continue; // first root wins (installed/repo before private)

        Entry e;
        e.id = name;
        e.absPath = fi.absoluteFilePath();
        e.origin = origin;
        e.byteSize = fi.size();
        e.isVideo = isVideo;
        e.invalid = !(isVideo ? validVideo : validImage);
        m_absById.insert(name, e.absPath);
        m_originById.insert(name, origin);
        m_all.append(e);
    }
}

void WallpaperGalleryModel::rebuildVisible()
{
    beginResetModel();
    m_visible.clear();
    for (const Entry &e : m_all) {
        if (passesFilter(e, m_filter))
            m_visible.append(e);
    }
    endResetModel();
    emit countChanged();
}

void WallpaperGalleryModel::enqueueMissingPosters()
{
    if (!isVideoGallery())
        return;
    // Keep in-flight poster; only queue ids that lack a cached frame and are
    // not already pending/queued — avoids restarting FFmpeg for every import.
    QSet<QString> queued(m_posterQueue.begin(), m_posterQueue.end());
    if (!m_posterPending.isEmpty())
        queued.insert(m_posterPending);
    for (const Entry &e : m_visible) {
        if (m_posters.contains(e.id) || queued.contains(e.id))
            continue;
        m_posterQueue.append(e.id);
        queued.insert(e.id);
    }
    startNextPoster();
}

void WallpaperGalleryModel::reload()
{
    beginResetModel();
    m_all.clear();
    m_visible.clear();
    m_absById.clear();
    m_originById.clear();
    // Do not kill an in-flight poster or wipe m_posters — import/folder watch
    // reloads must not restart the full FFmpeg queue per file.

    m_roots = resolveGalleryRoots(m_repoPath, m_extraFolders);
    m_galleryPath = m_roots.isEmpty() ? resolveInstalledGalleryPath() : m_roots.constFirst();

    const QStringList nameFilters = isVideoGallery() ? videoFilters() : imageFilters();
    const QString installed = QFileInfo(resolveInstalledGalleryPath()).absoluteFilePath();
    const QString repo = QFileInfo(resolveRepoGalleryPath(m_repoPath)).absoluteFilePath();
    const QString priv = QFileInfo(resolvePrivateGalleryPath()).absoluteFilePath();

    for (const QString &root : m_roots) {
        Origin origin = Origin::Extra;
        if (root == installed)
            origin = Origin::Installed;
        else if (root == repo)
            origin = Origin::Repo;
        else if (root == priv)
            origin = Origin::Private;
        appendFromDir(root, origin, nameFilters);
    }

    if (m_all.isEmpty())
        qWarning(lcWallGallery) << "gallery empty — roots:" << m_roots;

    qInfo(lcWallGallery) << "gallery roots" << m_roots << (isVideoGallery() ? "videos" : "images")
                         << "count" << m_all.size();

    for (const Entry &e : m_all) {
        if (passesFilter(e, m_filter))
            m_visible.append(e);
    }

    endResetModel();
    emit countChanged();
    emit rootsChanged();

    setupWatcher();
    enqueueMissingPosters();
}

void WallpaperGalleryModel::refreshGallery()
{
    reload();
}

void WallpaperGalleryModel::scheduleReload()
{
    if (m_reloadQueued)
        return;
    m_reloadQueued = true;
    m_reloadDebounce->start();
}

void WallpaperGalleryModel::setupWatcher()
{
    if (!m_watcher) {
        m_watcher = new QFileSystemWatcher(this);
        connect(m_watcher, &QFileSystemWatcher::directoryChanged, this,
                [this](const QString &) { scheduleReload(); });
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this,
                [this](const QString &) { scheduleReload(); });
    }

    const QStringList watchedDirs = m_watcher->directories();
    if (!watchedDirs.isEmpty())
        m_watcher->removePaths(watchedDirs);
    const QStringList watchedFiles = m_watcher->files();
    if (!watchedFiles.isEmpty())
        m_watcher->removePaths(watchedFiles);

    QStringList toWatch;
    for (const QString &root : m_roots) {
        if (QDir(root).exists())
            toWatch.append(root);
    }
    // Always watch private path so first import recreates the watcher target.
    const QString priv = resolvePrivateGalleryPath();
    if (QDir(priv).exists() || QDir().mkpath(priv))
        toWatch.append(QFileInfo(priv).absoluteFilePath());

    toWatch.removeDuplicates();
    if (!toWatch.isEmpty())
        m_watcher->addPaths(toWatch);

    const bool nowWatching = !m_watcher->directories().isEmpty();
    if (nowWatching != m_watching) {
        m_watching = nowWatching;
        emit watchingChanged();
    }
}

void WallpaperGalleryModel::loadExtraFolders()
{
    QSettings settings(QStringLiteral("Ryoku"), QStringLiteral("Settings"));
    m_extraFolders = settings.value(QStringLiteral("wallpaper/extraFolders")).toStringList();
    m_extraFolders.removeDuplicates();
}

void WallpaperGalleryModel::saveExtraFolders() const
{
    QSettings settings(QStringLiteral("Ryoku"), QStringLiteral("Settings"));
    settings.setValue(QStringLiteral("wallpaper/extraFolders"), m_extraFolders);
}

bool WallpaperGalleryModel::ensurePrivateDir(QString *errorOut) const
{
    const QString priv = resolvePrivateGalleryPath();
    if (pathLooksLikeNixStore(priv)) {
        if (errorOut)
            *errorOut = QStringLiteral("private gallery resolves into Nix store");
        return false;
    }
    if (!QDir().mkpath(priv)) {
        if (errorOut)
            *errorOut = QStringLiteral("cannot create private gallery");
        return false;
    }
    return true;
}

QString WallpaperGalleryModel::repoWallpapersDir() const
{
    if (m_repoPath.isEmpty())
        return {};
    return QDir(m_repoPath).filePath(QStringLiteral("distro/assets/wallpapers"));
}

bool WallpaperGalleryModel::openGalleryFolder(const QString &which)
{
    setLastError({});
    QString target;
    const QString w = which.trimmed().toLower();
    if (w == QLatin1String("private"))
        target = resolvePrivateGalleryPath();
    else if (w == QLatin1String("repository") || w == QLatin1String("repo"))
        target = resolveRepoGalleryPath(m_repoPath);
    else if (w == QLatin1String("installed"))
        target = resolveInstalledGalleryPath();
    else if (!w.isEmpty() && QDir(which).exists())
        target = QFileInfo(which).absoluteFilePath();
    else
        target = m_galleryPath.isEmpty() ? resolvePrivateGalleryPath() : m_galleryPath;

    if (target.isEmpty()) {
        setLastError(QStringLiteral("No gallery folder to open"));
        return false;
    }
    QDir().mkpath(target);
    if (!QDesktopServices::openUrl(QUrl::fromLocalFile(target))) {
        setLastError(QStringLiteral("Could not open folder"));
        return false;
    }
    return true;
}

bool WallpaperGalleryModel::addExtraFolder(const QString &dirPath)
{
    setLastError({});
    const QFileInfo fi(dirPath);
    if (!fi.exists() || !fi.isDir()) {
        setLastError(QStringLiteral("Folder not found"));
        return false;
    }
    if (pathLooksLikeNixStore(fi.absoluteFilePath())) {
        setLastError(QStringLiteral("Cannot watch a Nix store path as an extra folder"));
        return false;
    }
    const QString abs = fi.absoluteFilePath();
    if (m_extraFolders.contains(abs))
        return true;
    m_extraFolders.append(abs);
    saveExtraFolders();
    emit extraFoldersChanged();
    reload();
    return true;
}

bool WallpaperGalleryModel::addExtraFolderUrl(const QUrl &folderUrl)
{
    setLastError({});
    if (!folderUrl.isValid() || folderUrl.isEmpty()) {
        // Cancel / empty — no-op success so QML does not show a spurious error.
        return true;
    }
    if (!folderUrl.isLocalFile()) {
        setLastError(QStringLiteral("Folder URL is not a local path"));
        return false;
    }
    const QString path = folderUrl.toLocalFile();
    if (path.isEmpty()) {
        setLastError(QStringLiteral("Could not resolve folder path"));
        return false;
    }
    const QFileInfo fi(path);
    if (!fi.exists() || !fi.isDir() || !fi.isReadable()) {
        setLastError(QStringLiteral("Folder not found"));
        return false;
    }
    return addExtraFolder(fi.absoluteFilePath());
}

bool WallpaperGalleryModel::removeExtraFolder(const QString &dirPath)
{
    const QString abs = QFileInfo(dirPath).absoluteFilePath();
    if (!m_extraFolders.removeAll(abs))
        return false;
    saveExtraFolders();
    emit extraFoldersChanged();
    reload();
    return true;
}

QString WallpaperGalleryModel::importFileNoReload(const QString &sourcePath, bool enforceKind)
{
    setLastError({});
    const QFileInfo src(sourcePath);
    if (!src.exists() || !src.isFile() || !src.isReadable()) {
        setLastError(QStringLiteral("File not found"));
        return {};
    }

    const QString name = src.fileName();
    const bool okImage = SettingsStore::isValidWallpaperId(name);
    const bool okVideo = SettingsStore::isValidVideoWallpaperId(name);
    if (!okImage && !okVideo) {
        setLastError(QStringLiteral("Unsupported or unsafe wallpaper name"));
        return {};
    }
    if (enforceKind) {
        if (m_kind == MediaKind::Images && !okImage) {
            setLastError(QStringLiteral("Not an image wallpaper"));
            return {};
        }
        if (m_kind == MediaKind::Videos && !okVideo) {
            setLastError(QStringLiteral("Not a video wallpaper"));
            return {};
        }
    }

    QString err;
    if (!ensurePrivateDir(&err)) {
        setLastError(err);
        return {};
    }

    const QString dest = ensureWritableCopy(src.absoluteFilePath(), resolvePrivateGalleryPath(),
                                            name, &err);
    if (dest.isEmpty()) {
        setLastError(err.isEmpty() ? QStringLiteral("Import failed") : err);
        return {};
    }

    const QString imported = QFileInfo(dest).fileName();
    qInfo(lcWallGallery) << "imported private wallpaper" << imported;
    return imported;
}

QString WallpaperGalleryModel::importFile(const QString &sourcePath)
{
    const QString imported = importFileNoReload(sourcePath);
    if (imported.isEmpty())
        return {};
    m_lastImportedIds = {imported};
    m_lastIgnoredCount = 0;
    m_lastRejectedCount = 0;
    emit lastImportedIdsChanged();
    setLastImportSummary(
        QCoreApplication::translate("WallpaperGalleryModel", "Imported %1 · ignored %2 · rejected %3")
            .arg(1)
            .arg(0)
            .arg(0));
    reload();
    return imported;
}

QStringList WallpaperGalleryModel::importFiles(const QStringList &sourcePaths)
{
    QStringList imported;
    QStringList errors;
    QStringList ignored;
    setImportBusy(true);
    setImportProgress(0);
    const int total = sourcePaths.size();
    int i = 0;
    for (const QString &path : sourcePaths) {
        ++i;
        if (total > 0)
            setImportProgress(int((i - 1) * 100.0 / total));
        const QString name = QFileInfo(path).fileName();
        const QString kind = mediaKindForFileName(name);
        const bool matching = (m_kind == MediaKind::Images && kind == QLatin1String("image"))
            || (m_kind == MediaKind::Videos && kind == QLatin1String("video"));
        if (!kind.isEmpty() && !matching) {
            ignored.append(name);
            continue;
        }
        const QString id = importFileNoReload(path);
        if (id.isEmpty())
            errors.append(QStringLiteral("%1: %2").arg(name, m_lastError));
        else
            imported.append(id);
    }
    m_lastImportedIds = imported;
    m_lastIgnoredCount = ignored.size();
    m_lastRejectedCount = errors.size();
    emit lastImportedIdsChanged();
    if (!errors.isEmpty())
        setLastError(errors.join(QLatin1Char('\n')));
    else
        setLastError({});
    setLastImportSummary(
        QCoreApplication::translate("WallpaperGalleryModel", "Imported %1 · ignored %2 · rejected %3")
            .arg(imported.size())
            .arg(ignored.size())
            .arg(errors.size()));
    if (!imported.isEmpty())
        reload();
    setImportProgress(100);
    setImportBusy(false);
    return imported;
}

QVariantMap WallpaperGalleryModel::importUrls(const QVariantList &urls)
{
    QVariantMap out;
    QStringList imported;
    QStringList rejected;
    QStringList errors;

    // Empty selection / cancel → no-op.
    if (urls.isEmpty()) {
        out.insert(QStringLiteral("imported"), QStringList{});
        out.insert(QStringLiteral("ignored"), QStringList{});
        out.insert(QStringLiteral("rejected"), QStringList{});
        out.insert(QStringLiteral("importedCount"), 0);
        out.insert(QStringLiteral("ignoredCount"), 0);
        out.insert(QStringLiteral("rejectedCount"), 0);
        out.insert(QStringLiteral("summary"), QString{});
        out.insert(QStringLiteral("error"), QString{});
        out.insert(QStringLiteral("ok"), true);
        return out;
    }

    setImportBusy(true);
    setImportProgress(0);
    setLastError({});

    const int total = urls.size();
    int index = 0;
    for (const QVariant &v : urls) {
        ++index;
        if (total > 0)
            setImportProgress(int((index - 1) * 100.0 / total));

        const QUrl url = coerceToUrl(v);
        if (!url.isValid() || url.isEmpty()) {
            rejected.append(QStringLiteral("(empty)"));
            errors.append(QStringLiteral("empty URL"));
            continue;
        }
        if (!url.isLocalFile()) {
            rejected.append(url.toString());
            errors.append(QStringLiteral("%1: not a local file").arg(url.toString()));
            continue;
        }
        const QString path = url.toLocalFile();
        if (path.isEmpty()) {
            rejected.append(url.toString());
            errors.append(QStringLiteral("%1: toLocalFile failed").arg(url.toString()));
            continue;
        }
        const QFileInfo fi(path);
        if (!fi.exists() || !fi.isFile() || !fi.isReadable()) {
            rejected.append(fi.fileName().isEmpty() ? path : fi.fileName());
            errors.append(QStringLiteral("%1: not found or not readable").arg(fi.fileName()));
            continue;
        }

        const QString name = fi.fileName();
        const QString kind = mediaKindForFileName(name);
        if (kind.isEmpty()) {
            rejected.append(name);
            errors.append(QStringLiteral("%1: unsupported type").arg(name));
            continue;
        }

        // Classify by extension; import into shared private library without
        // enforcing this model's MediaKind (sibling gallery refreshes via watcher).
        const QString id = importFileNoReload(fi.absoluteFilePath(), /*enforceKind=*/false);
        if (id.isEmpty()) {
            rejected.append(name);
            errors.append(QStringLiteral("%1: %2").arg(name, m_lastError));
        } else {
            imported.append(id);
        }
    }

    m_lastImportedIds = imported;
    m_lastIgnoredCount = 0;
    m_lastRejectedCount = rejected.size();
    emit lastImportedIdsChanged();

    const QString summary =
        QCoreApplication::translate("WallpaperGalleryModel", "Imported %1 · ignored %2 · rejected %3")
            .arg(imported.size())
            .arg(0)
            .arg(rejected.size());
    setLastImportSummary(summary);
    if (!errors.isEmpty())
        setLastError(errors.join(QLatin1Char('\n')));
    else
        setLastError({});

    if (!imported.isEmpty())
        reload();

    setImportProgress(100);
    setImportBusy(false);

    out.insert(QStringLiteral("imported"), imported);
    out.insert(QStringLiteral("ignored"), QStringList{});
    out.insert(QStringLiteral("rejected"), rejected);
    out.insert(QStringLiteral("importedCount"), imported.size());
    out.insert(QStringLiteral("ignoredCount"), 0);
    out.insert(QStringLiteral("rejectedCount"), rejected.size());
    out.insert(QStringLiteral("summary"), summary);
    out.insert(QStringLiteral("error"), m_lastError);
    out.insert(QStringLiteral("ok"), rejected.isEmpty());
    return out;
}

QVariantMap WallpaperGalleryModel::publishPreview(const QString &id) const
{
    QVariantMap out;
    out.insert(QStringLiteral("id"), id);
    out.insert(QStringLiteral("ok"), false);
    if (!m_absById.contains(id)) {
        out.insert(QStringLiteral("error"), QStringLiteral("Wallpaper not in gallery"));
        return out;
    }
    const QString abs = m_absById.value(id);
    const QFileInfo fi(abs);
    const QString destDir = repoWallpapersDir();
    const QString destRel = QStringLiteral("distro/assets/wallpapers/%1").arg(id);
    out.insert(QStringLiteral("sourcePath"), abs);
    out.insert(QStringLiteral("destDir"), destDir);
    out.insert(QStringLiteral("destRelative"), destRel);
    out.insert(QStringLiteral("byteSize"), fi.size());
    out.insert(QStringLiteral("origin"), originKey(m_originById.value(id, Origin::Private)));
    out.insert(QStringLiteral("isVideo"),
               SettingsStore::isValidVideoWallpaperId(id));
    const bool overLimit = fi.size() > githubSoftLimitBytes();
    out.insert(QStringLiteral("exceedsGitHubLimit"), overLimit);
    out.insert(QStringLiteral("githubLimitBytes"), githubSoftLimitBytes());
    if (destDir.isEmpty()) {
        out.insert(QStringLiteral("error"), QStringLiteral("Repository path unavailable"));
        return out;
    }
    if (overLimit) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("File exceeds GitHub 100 MiB limit; Git LFS is not enabled"));
        return out;
    }
    out.insert(QStringLiteral("ok"), true);
    return out;
}

QVariantMap WallpaperGalleryModel::includeInRepository(const QString &id)
{
    QVariantMap preview = publishPreview(id);
    if (!preview.value(QStringLiteral("ok")).toBool()) {
        setLastError(preview.value(QStringLiteral("error")).toString());
        emit repositoryIncludeFinished(false, {});
        return preview;
    }

    const QString abs = preview.value(QStringLiteral("sourcePath")).toString();
    const QString destDir = preview.value(QStringLiteral("destDir")).toString();
    QString err;
    const QString dest = ensureWritableCopy(abs, destDir, id, &err);
    if (dest.isEmpty()) {
        preview.insert(QStringLiteral("ok"), false);
        preview.insert(QStringLiteral("error"), err);
        setLastError(err);
        emit repositoryIncludeFinished(false, {});
        return preview;
    }

    const QString finalId = QFileInfo(dest).fileName();
    const QString rel = QStringLiteral("distro/assets/wallpapers/%1").arg(finalId);
    preview.insert(QStringLiteral("ok"), true);
    preview.insert(QStringLiteral("id"), finalId);
    preview.insert(QStringLiteral("destRelative"), rel);
    preview.insert(QStringLiteral("destPath"), dest);
    setLastError({});
    setLastImportSummary(
        QCoreApplication::translate("WallpaperGalleryModel", "Copied to %1").arg(rel));
    reload();
    emit repositoryIncludeFinished(true, rel);
    return preview;
}

void WallpaperGalleryModel::requestManageChanges()
{
    emit manageChangesRequested();
}

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
                    const QString out =
                        QString::fromUtf8(m_posterProc->readAllStandardOutput()).trimmed();
                    const QString poster = out.section(QLatin1Char('\n'), -1).trimmed();
                    if (status == QProcess::NormalExit && exitCode == 0 && QFileInfo(poster).isFile()) {
                        m_posters.insert(id, poster);
                        for (int row = 0; row < m_visible.size(); ++row) {
                            if (m_visible.at(row).id == id) {
                                const QModelIndex idx = index(row);
                                emit dataChanged(idx, idx, {PosterUrlRole});
                                break;
                            }
                        }
                        ++m_posterRevision;
                        emit postersChanged();
                    } else {
                        qWarning(lcWallGallery)
                            << "poster failed for" << id
                            << QString::fromUtf8(m_posterProc->readAllStandardError()).trimmed();
                    }
                    startNextPoster();
                });
    }

    m_posterPending = m_posterQueue.takeFirst();
    // Skip if a cached poster already exists from a prior session via helper.
    m_posterProc->start(helper, {QStringLiteral("poster"), m_absById.value(m_posterPending)});
}

int WallpaperGalleryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_visible.size();
}

QVariant WallpaperGalleryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visible.size())
        return {};

    const Entry &e = m_visible.at(index.row());

    switch (role) {
    case FileNameRole:
        return e.id;
    case AbsolutePathRole:
        return e.absPath;
    case UrlRole:
        return QUrl::fromLocalFile(e.absPath);
    case IsVideoRole:
        return e.isVideo;
    case PosterUrlRole:
        return posterUrlForId(e.id);
    case OriginRole:
        return originKey(e.origin);
    case OriginLabelRole:
        return originLabel(e.origin);
    case ByteSizeRole:
        return e.byteSize;
    case InRepositoryRole:
        return e.origin == Origin::Repo || e.origin == Origin::Installed;
    case InvalidRole:
        return e.invalid;
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
        {OriginRole, "origin"},
        {OriginLabelRole, "originLabel"},
        {ByteSizeRole, "byteSize"},
        {InRepositoryRole, "inRepository"},
        {InvalidRole, "invalid"},
    };
}

QString WallpaperGalleryModel::absolutePathForId(const QString &id) const
{
    if (!isValidId(id))
        return {};
    QString candidate = m_absById.value(id);
    if (candidate.isEmpty()) {
        // Fallback scan of known roots (settings restore before first reload edge).
        for (const QString &root : resolveGalleryRoots(m_repoPath, m_extraFolders)) {
            const QString probe = QDir(root).filePath(id);
            if (QFileInfo::exists(probe)) {
                candidate = QFileInfo(probe).absoluteFilePath();
                break;
            }
        }
    }
    if (candidate.isEmpty())
        return {};
    const QFileInfo fi(candidate);
    if (!fi.exists() || !fi.isFile())
        return {};
    if (fi.fileName() != id)
        return {};
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

QString WallpaperGalleryModel::originForId(const QString &id) const
{
    if (!m_originById.contains(id))
        return {};
    return originKey(m_originById.value(id));
}
