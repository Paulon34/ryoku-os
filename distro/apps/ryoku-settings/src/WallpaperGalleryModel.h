#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QUrl>

class QProcess;

// Lists Ryoku-managed wallpapers (basename ids) from the allowed gallery dir.
// Images by default; a Videos instance lists video wallpapers and resolves
// their cached poster frames via `ryoku-video-wallpaper poster` (one-shot).
class WallpaperGalleryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QString galleryPath READ galleryPath NOTIFY countChanged)
    Q_PROPERTY(bool videos READ isVideoGallery CONSTANT)
    // Bumped when a poster becomes available — lets QML bindings on posterUrlForId() refresh.
    Q_PROPERTY(int posterRevision READ posterRevision NOTIFY postersChanged)

public:
    enum Roles {
        FileNameRole = Qt::UserRole + 1,
        AbsolutePathRole,
        UrlRole,
        IsVideoRole,
        PosterUrlRole
    };

    enum class MediaKind { Images, Videos };

    explicit WallpaperGalleryModel(QObject *parent = nullptr);
    explicit WallpaperGalleryModel(MediaKind kind, QObject *parent = nullptr);

    void setRepoPath(const QString &repoPath);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString galleryPath() const { return m_galleryPath; }
    bool isVideoGallery() const { return m_kind == MediaKind::Videos; }
    int posterRevision() const { return m_posterRevision; }

    Q_INVOKABLE void reload();
    Q_INVOKABLE QString absolutePathForId(const QString &id) const;
    Q_INVOKABLE QUrl urlForId(const QString &id) const;
    // Videos: cached poster frame (empty until generated). Images: same as urlForId.
    Q_INVOKABLE QUrl posterUrlForId(const QString &id) const;

    bool isValidId(const QString &id) const;

    // Resolve allowed gallery root (prefer ~/.local/share/wallpapers).
    static QString resolveGalleryPath(const QString &repoPath);
    static QString findVideoHelper();

signals:
    void countChanged();
    void postersChanged();

private:
    void startNextPoster();

    MediaKind m_kind = MediaKind::Images;
    QString m_repoPath;
    QString m_galleryPath;
    QStringList m_files; // basenames
    QHash<QString, QString> m_posters; // basename → poster absolute path
    QStringList m_posterQueue;
    QProcess *m_posterProc = nullptr;
    QString m_posterPending;
    int m_posterRevision = 0;
};
