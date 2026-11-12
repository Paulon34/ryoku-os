#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class QProcess;
class QTimer;

// Live wallpaper apply via existing DMS IPC (same as scripts/change-wallpaper.sh).
// Video wallpapers go through `ryoku-video-wallpaper` (poster → DMS/Matugen,
// mpvpaper user unit). QProcess argv only — never shell.
class WallpaperApplier : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY finished)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit WallpaperApplier(QObject *parent = nullptr);

    void setGalleryModel(class WallpaperGalleryModel *gallery);
    void setVideoGalleryModel(class WallpaperGalleryModel *gallery);

    QString lastError() const { return m_lastError; }
    bool busy() const { return m_busy || m_helperRunning; }

    // relativeId = basename e.g. "1.jpg". Resolves via gallery, then:
    //   dms ipc call wallpaper set <absolute>
    // and stops an active video wallpaper.
    Q_INVOKABLE bool applyWallpaper(const QString &relativeId);
    // Sets the DMS theme via its supported settings IPC, then applies the
    // wallpaper. The Settings checkbox must control real Material You mode.
    Q_INVOKABLE bool applyWallpaperWithTheme(const QString &relativeId, bool dynamicColors);
    Q_INVOKABLE bool setDynamicColors(bool enabled);

    // Asynchronous; result via videoApplyFinished. profile: economy|balanced|quality.
    Q_INVOKABLE bool applyVideoWallpaper(const QString &relativeId,
                                         bool loop,
                                         bool audio,
                                         const QString &profile,
                                         bool pauseWhenCovered);

    static QString findDmsBinary();
    static QStringList videoApplyArguments(const QString &absolutePath,
                                           bool loop,
                                           bool audio,
                                           const QString &profile,
                                           bool pauseWhenCovered);

signals:
    void finished(bool ok);
    void videoApplyFinished(bool ok);
    void busyChanged();

private:
    bool runHelper(const QStringList &args, bool reportVideoResult);

    WallpaperGalleryModel *m_gallery = nullptr;
    WallpaperGalleryModel *m_videoGallery = nullptr;
    QString m_lastError;
    bool m_busy = false;
    bool m_helperRunning = false;
    bool m_reportVideoResult = false;
    QProcess *m_helper = nullptr;
    QTimer *m_helperTimeout = nullptr;
};
