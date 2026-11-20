#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

class QFileSystemWatcher;
class QProcess;
class QTimer;

// Unified Ryoku wallpaper gallery: installed (HM) + repo checkout + private
// library + user extra folders. MediaKind still splits image/video instances
// used by WallpaperApplier; Filter further narrows the visible rows.
class WallpaperGalleryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QString galleryPath READ galleryPath NOTIFY rootsChanged)
    Q_PROPERTY(QStringList galleryRoots READ galleryRoots NOTIFY rootsChanged)
    Q_PROPERTY(bool videos READ isVideoGallery CONSTANT)
    Q_PROPERTY(int posterRevision READ posterRevision NOTIFY postersChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QStringList extraFolders READ extraFolders NOTIFY extraFoldersChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString lastImportSummary READ lastImportSummary NOTIFY lastImportSummaryChanged)
    Q_PROPERTY(bool watching READ watching NOTIFY watchingChanged)

public:
    enum Roles {
        FileNameRole = Qt::UserRole + 1,
        AbsolutePathRole,
        UrlRole,
        IsVideoRole,
        PosterUrlRole,
        OriginRole,
        OriginLabelRole,
        ByteSizeRole,
        InRepositoryRole,
        InvalidRole
    };

    enum class MediaKind { Images, Videos };
    // Origin of the first winning path for a basename (public before private).
    enum class Origin { Installed, Repo, Private, Extra };

    explicit WallpaperGalleryModel(QObject *parent = nullptr);
    explicit WallpaperGalleryModel(MediaKind kind, QObject *parent = nullptr);
    ~WallpaperGalleryModel() override;

    void setRepoPath(const QString &repoPath);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString galleryPath() const { return m_galleryPath; }
    QStringList galleryRoots() const { return m_roots; }
    bool isVideoGallery() const { return m_kind == MediaKind::Videos; }
    int posterRevision() const { return m_posterRevision; }
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    QStringList extraFolders() const { return m_extraFolders; }
    QString lastError() const { return m_lastError; }
    QString lastImportSummary() const { return m_lastImportSummary; }
    bool watching() const { return m_watching; }

    Q_INVOKABLE void reload();
    Q_INVOKABLE void refreshGallery();
    Q_INVOKABLE QString absolutePathForId(const QString &id) const;
    Q_INVOKABLE QUrl urlForId(const QString &id) const;
    // Videos: cached poster frame (empty until generated). Images: same as urlForId.
    Q_INVOKABLE QUrl posterUrlForId(const QString &id) const;
    Q_INVOKABLE QString originForId(const QString &id) const;
    Q_INVOKABLE bool openGalleryFolder(const QString &which = QString());
    Q_INVOKABLE bool addExtraFolder(const QString &dirPath);
    Q_INVOKABLE bool removeExtraFolder(const QString &dirPath);
    // Copy into private library (never git). Returns imported basename or empty.
    Q_INVOKABLE QString importFile(const QString &sourcePath);
    Q_INVOKABLE QStringList importFiles(const QStringList &sourcePaths);
    // Explicit opt-in: copy into distro/assets/wallpapers/ for git staging.
    Q_INVOKABLE QVariantMap includeInRepository(const QString &id);
    Q_INVOKABLE QVariantMap publishPreview(const QString &id) const;
    Q_INVOKABLE void requestManageChanges();

    bool isValidId(const QString &id) const;

    // All discovery roots (installed, repo assets, private, extras). Never
    // returns only the first hit — callers merge every existing directory.
    static QStringList resolveGalleryRoots(const QString &repoPath,
                                           const QStringList &extraFolders = {});
    static QString resolveInstalledGalleryPath();
    static QString resolveRepoGalleryPath(const QString &repoPath);
    // Prefer ~/.local/share/wallpapers when present (compat with older callers).
    static QString resolveGalleryPath(const QString &repoPath);
    static QString resolvePrivateGalleryPath();
    static QString findVideoHelper();
    static bool pathLooksLikeNixStore(const QString &path);
    // Writable copy destination when source is a store symlink/file.
    static QString ensureWritableCopy(const QString &sourceAbs, const QString &destDir,
                                      const QString &preferredName, QString *errorOut = nullptr);
    static QString uniqueDestName(const QString &dirPath, const QString &preferredName);
    // GitHub soft limit without LFS (bytes).
    static qint64 githubSoftLimitBytes() { return 100LL * 1024 * 1024; }

signals:
    void countChanged();
    void postersChanged();
    void rootsChanged();
    void filterChanged();
    void extraFoldersChanged();
    void lastErrorChanged();
    void lastImportSummaryChanged();
    void watchingChanged();
    void manageChangesRequested();
    void repositoryIncludeFinished(bool ok, const QString &relativePath);

private:
    struct Entry {
        QString id;
        QString absPath;
        Origin origin = Origin::Installed;
        qint64 byteSize = 0;
        bool invalid = false;
        bool isVideo = false;
    };

    void startNextPoster();
    void appendFromDir(const QString &dirPath, Origin origin, const QStringList &nameFilters);
    void rebuildVisible();
    void setupWatcher();
    void scheduleReload();
    void loadExtraFolders();
    void saveExtraFolders() const;
    void setLastError(const QString &err);
    void setLastImportSummary(const QString &summary);
    bool ensurePrivateDir(QString *errorOut) const;
    QString repoWallpapersDir() const;
    static QString originKey(Origin o);
    static QString originLabel(Origin o);
    static bool passesFilter(const Entry &e, const QString &filter);

    MediaKind m_kind = MediaKind::Images;
    QString m_repoPath;
    QString m_galleryPath;
    QStringList m_roots;
    QStringList m_extraFolders;
    QString m_filter = QStringLiteral("all");
    QString m_lastError;
    QString m_lastImportSummary;

    QList<Entry> m_all;
    QList<Entry> m_visible;
    QHash<QString, QString> m_absById;
    QHash<QString, Origin> m_originById;
    QHash<QString, QString> m_posters;
    QStringList m_posterQueue;
    QProcess *m_posterProc = nullptr;
    QString m_posterPending;
    int m_posterRevision = 0;

    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_reloadDebounce = nullptr;
    bool m_watching = false;
    bool m_reloadQueued = false;
};
