#include "WallpaperApplier.h"
#include "WallpaperGalleryModel.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIODevice>
#include <QLoggingCategory>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

Q_LOGGING_CATEGORY(lcWallApply, "ryoku.settings.wallpaper.apply")

WallpaperApplier::WallpaperApplier(QObject *parent)
    : QObject(parent)
{
}

void WallpaperApplier::setGalleryModel(WallpaperGalleryModel *gallery)
{
    m_gallery = gallery;
}

void WallpaperApplier::setVideoGalleryModel(WallpaperGalleryModel *gallery)
{
    m_videoGallery = gallery;
}

QString WallpaperApplier::findDmsBinary()
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("dms"));
    if (!fromPath.isEmpty())
        return fromPath;

    // Common NixOS system profile location when PATH is minimal (e.g. nix run).
    const QString systemPath = QStringLiteral("/run/current-system/sw/bin/dms");
    if (QFileInfo::exists(systemPath) && QFileInfo(systemPath).isExecutable())
        return systemPath;

    return {};
}

QStringList WallpaperApplier::videoApplyArguments(const QString &absolutePath,
                                                  bool loop,
                                                  bool audio,
                                                  const QString &profile,
                                                  bool pauseWhenCovered)
{
    const QString p = (profile == QStringLiteral("economy") || profile == QStringLiteral("quality"))
        ? profile
        : QStringLiteral("balanced");
    return {
        QStringLiteral("apply"),
        absolutePath,
        QStringLiteral("--loop"), loop ? QStringLiteral("1") : QStringLiteral("0"),
        QStringLiteral("--audio"), audio ? QStringLiteral("1") : QStringLiteral("0"),
        QStringLiteral("--profile"), p,
        QStringLiteral("--pause-covered"), pauseWhenCovered ? QStringLiteral("1") : QStringLiteral("0"),
    };
}

bool WallpaperApplier::applyWallpaper(const QString &relativeId)
{
    m_lastError.clear();

    if (busy()) {
        m_lastError = QStringLiteral("Wallpaper apply already in progress");
        emit finished(false);
        return false;
    }

    if (!m_gallery) {
        m_lastError = QStringLiteral("Gallery unavailable");
        emit finished(false);
        return false;
    }

    const QString abs = m_gallery->absolutePathForId(relativeId);
    if (abs.isEmpty()) {
        m_lastError = QStringLiteral("Wallpaper not found or path rejected");
        qWarning(lcWallApply) << m_lastError << relativeId;
        emit finished(false);
        return false;
    }

    const QString dms = findDmsBinary();
    if (dms.isEmpty()) {
        m_lastError = QStringLiteral("dms not found on PATH");
        qWarning(lcWallApply) << m_lastError;
        emit finished(false);
        return false;
    }

    m_busy = true;
    emit busyChanged();

    QProcess proc;
    proc.setProgram(dms);
    // Same contract as scripts/change-wallpaper.sh — no shell.
    proc.setArguments({
        QStringLiteral("ipc"),
        QStringLiteral("call"),
        QStringLiteral("wallpaper"),
        QStringLiteral("set"),
        abs,
    });
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start();

    if (!proc.waitForFinished(20000)) {
        proc.kill();
        m_busy = false;
        emit busyChanged();
        m_lastError = QStringLiteral("dms wallpaper set timed out");
        qWarning(lcWallApply) << m_lastError;
        emit finished(false);
        return false;
    }

    m_busy = false;
    emit busyChanged();

    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        m_lastError = QString::fromUtf8(proc.readAll()).trimmed();
        if (m_lastError.isEmpty())
            m_lastError = QStringLiteral("dms wallpaper set failed (exit %1)").arg(proc.exitCode());
        qWarning(lcWallApply) << m_lastError;
        emit finished(false);
        return false;
    }

    qInfo(lcWallApply) << "applied wallpaper" << relativeId << "via" << abs;

    // Persist for Matugen / next session (Debian Modular path).
    {
        const QString ryokuDir =
            QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
                .filePath(QStringLiteral(".config/ryoku"));
        QDir().mkpath(ryokuDir);
        const QString link = ryokuDir + QStringLiteral("/current-wallpaper");
        QFile::remove(link);
        if (!QFile::link(abs, link))
            qWarning(lcWallApply) << "failed to update current-wallpaper symlink";
        QFile idFile(ryokuDir + QStringLiteral("/current-wallpaper-id"));
        if (idFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            idFile.write(relativeId.toUtf8());
            idFile.write("\n");
        }
        // Refresh Material You templates for Hyprland/Niri colors.
        const QString matugen = QStandardPaths::findExecutable(QStringLiteral("matugen"));
        if (!matugen.isEmpty()) {
            QProcess mg;
            mg.setProgram(matugen);
            mg.setArguments({QStringLiteral("image"), abs});
            mg.start();
            mg.waitForFinished(30000);
        }
    }

    // DMS already shows the image; the helper reveals it over a running video
    // and then stops mpvpaper (no-op when no video is active).
    runHelper({QStringLiteral("stop")}, false);

    emit finished(true);
    return true;
}

bool WallpaperApplier::applyVideoWallpaper(const QString &relativeId,
                                           bool loop,
                                           bool audio,
                                           const QString &profile,
                                           bool pauseWhenCovered)
{
    m_lastError.clear();

    auto fail = [this](const QString &msg) {
        m_lastError = msg;
        qWarning(lcWallApply) << msg;
        emit finished(false);
        return false;
    };

    if (busy())
        return fail(QStringLiteral("Wallpaper apply already in progress"));
    if (!m_videoGallery)
        return fail(QStringLiteral("Video gallery unavailable"));

    const QString abs = m_videoGallery->absolutePathForId(relativeId);
    if (abs.isEmpty())
        return fail(QStringLiteral("Video not found or path rejected"));

    if (!runHelper(videoApplyArguments(abs, loop, audio, profile, pauseWhenCovered), true))
        return false;

    qInfo(lcWallApply) << "applying video wallpaper" << relativeId << "profile" << profile;
    return true;
}

// One helper at a time: stop (after an image) and apply (video) must not race,
// or a delayed stop could kill a video that was selected right after.
bool WallpaperApplier::runHelper(const QStringList &args, bool reportVideoResult)
{
    const QString helper = WallpaperGalleryModel::findVideoHelper();
    if (helper.isEmpty()) {
        if (!reportVideoResult)
            return true; // No video support installed → nothing to stop.
        m_lastError = QStringLiteral("ryoku-video-wallpaper not found on PATH");
        qWarning(lcWallApply) << m_lastError;
        emit finished(false);
        return false;
    }

    if (!m_helper) {
        m_helper = new QProcess(this);
        m_helper->setProcessChannelMode(QProcess::SeparateChannels);
        m_helperTimeout = new QTimer(this);
        m_helperTimeout->setSingleShot(true);
        m_helperTimeout->setInterval(30000);
        connect(m_helperTimeout, &QTimer::timeout, m_helper, &QProcess::kill);
        connect(m_helper, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) {
            m_helperTimeout->stop();
            m_helperRunning = false;
            const bool ok = status == QProcess::NormalExit && exitCode == 0;
            const QString err = QString::fromUtf8(m_helper->readAllStandardError()).trimmed();
            m_helper->readAllStandardOutput();
            if (!ok) {
                m_lastError = err.isEmpty()
                    ? QStringLiteral("ryoku-video-wallpaper failed (exit %1)").arg(exitCode)
                    : err.section(QLatin1Char('\n'), -1);
                qWarning(lcWallApply) << "ryoku-video-wallpaper:" << err;
            }
            emit busyChanged();
            if (m_reportVideoResult) {
                emit finished(ok);
                emit videoApplyFinished(ok);
            }
        });
        // FailedToStart never emits finished().
        connect(m_helper, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart)
                return;
            m_helperTimeout->stop();
            m_helperRunning = false;
            m_lastError = QStringLiteral("ryoku-video-wallpaper could not be started");
            qWarning(lcWallApply) << m_lastError;
            emit busyChanged();
            if (m_reportVideoResult) {
                emit finished(false);
                emit videoApplyFinished(false);
            }
        });
    }

    m_reportVideoResult = reportVideoResult;
    m_helperRunning = true;
    emit busyChanged();
    m_helper->start(helper, args);
    m_helperTimeout->start();
    return true;
}
