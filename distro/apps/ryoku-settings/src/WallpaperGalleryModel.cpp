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
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
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

void WallpaperGalleryModel::reload()
{
    beginResetModel();
    m_all.clear();
    m_visible.clear();
    m_absById.clear();
    m_originById.clear();
    m_posterQueue.clear();
    m_posterPending.clear();
    if (m_posterProc && m_posterProc->state() != QProcess::NotRunning) {
        m_posterProc->kill();
        m_posterProc->waitForFinished(2000);
    }

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

    if (isVideoGallery()) {
        m_posterQueue.clear();
        for (const Entry &e : m_visible)
            m_posterQueue.append(e.id);
        startNextPoster();
    }
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

QString WallpaperGalleryModel::importFile(const QString &sourcePath)
{
    setLastError({});
    const QFileInfo src(sourcePath);
    if (!src.exists() || !src.isFile()) {
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
    if (m_kind == MediaKind::Images && !okImage) {
        setLastError(QStringLiteral("Not an image wallpaper"));
        return {};
    }
    if (m_kind == MediaKind::Videos && !okVideo) {
        setLastError(QStringLiteral("Not a video wallpaper"));
        return {};
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
    reload();
    return imported;
}

QStringList WallpaperGalleryModel::importFiles(const QStringList &sourcePaths)
{
    QStringList imported;
    QStringList errors;
    for (const QString &path : sourcePaths) {
        const QString id = importFile(path);
        if (id.isEmpty())
            errors.append(QStringLiteral("%1: %2").arg(QFileInfo(path).fileName(), m_lastError));
        else
            imported.append(id);
    }
    if (!errors.isEmpty())
        setLastError(errors.join(QLatin1Char('\n')));
    setLastImportSummary(
        QCoreApplication::translate("WallpaperGalleryModel", "Imported %1 · skipped %2")
            .arg(imported.size())
            .arg(errors.size()));
    return imported;
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
