#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// Read-only system observability (7H-A). File reads + optional async hyprctl.
class SystemInfoModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString osPrettyName READ osPrettyName NOTIFY changed)
    Q_PROPERTY(QString osVersion READ osVersion NOTIFY changed)
    Q_PROPERTY(QString osId READ osId NOTIFY changed)
    Q_PROPERTY(QString kernel READ kernel NOTIFY changed)
    Q_PROPERTY(QString hostname READ hostname NOTIFY changed)
    Q_PROPERTY(QString architecture READ architecture NOTIFY changed)
    Q_PROPERTY(QString currentSystemPath READ currentSystemPath NOTIFY changed)
    Q_PROPERTY(QString profileSystemPath READ profileSystemPath NOTIFY changed)
    Q_PROPERTY(QString profileLinkName READ profileLinkName NOTIFY changed)
    Q_PROPERTY(int profileGeneration READ profileGeneration NOTIFY changed)
    Q_PROPERTY(bool generationPathsMatch READ generationPathsMatch NOTIFY changed)
    Q_PROPERTY(QString generationMatchLabel READ generationMatchLabel NOTIFY changed)
    Q_PROPERTY(QString hyprlandVersion READ hyprlandVersion NOTIFY changed)
    Q_PROPERTY(QString sessionType READ sessionType NOTIFY changed)
    Q_PROPERTY(QString desktopShell READ desktopShell NOTIFY changed)
    Q_PROPERTY(QString uptimeLabel READ uptimeLabel NOTIFY changed)
    Q_PROPERTY(QString cpuModel READ cpuModel NOTIFY changed)
    Q_PROPERTY(QString memoryTotalLabel READ memoryTotalLabel NOTIFY changed)
    Q_PROPERTY(QStringList gpuLabels READ gpuLabels NOTIFY changed)
    Q_PROPERTY(QString batterySummary READ batterySummary NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    explicit SystemInfoModel(QObject *parent = nullptr);
    ~SystemInfoModel() override;

    QString osPrettyName() const { return m_osPrettyName; }
    QString osVersion() const { return m_osVersion; }
    QString osId() const { return m_osId; }
    QString kernel() const { return m_kernel; }
    QString hostname() const { return m_hostname; }
    QString architecture() const { return m_architecture; }
    QString currentSystemPath() const { return m_currentSystemPath; }
    QString profileSystemPath() const { return m_profileSystemPath; }
    QString profileLinkName() const { return m_profileLinkName; }
    int profileGeneration() const { return m_profileGeneration; }
    bool generationPathsMatch() const { return m_generationPathsMatch; }
    QString generationMatchLabel() const { return m_generationMatchLabel; }
    QString hyprlandVersion() const { return m_hyprlandVersion; }
    QString sessionType() const { return m_sessionType; }
    QString desktopShell() const { return m_desktopShell; }
    QString uptimeLabel() const { return m_uptimeLabel; }
    QString cpuModel() const { return m_cpuModel; }
    QString memoryTotalLabel() const { return m_memoryTotalLabel; }
    QStringList gpuLabels() const { return m_gpuLabels; }
    QString batterySummary() const { return m_batterySummary; }
    bool busy() const { return m_busy; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void refresh();

    static QVariantMap parseOsRelease(const QByteArray &text);
    static QString parseCpuModel(const QByteArray &cpuinfo);
    static qint64 parseMemTotalKb(const QByteArray &meminfo);
    static QString formatMemoryFromKb(qint64 kb);
    static QString formatUptime(double seconds);
    static QString parseHyprctlVersionLine(const QByteArray &output);
    static QStringList parseDrmGpuLabels(const QStringList &drmEntries);
    static QStringList gpuLabelsFromSysfs();
    static QString canonicalPathOrEmpty(const QString &path);
    static bool pathsMatch(const QString &a, const QString &b);
    static QString generationMatchLabelFor(bool bothPresent, bool match);
    static QString pickOsReleasePath();
    static int parseProfileGeneration(const QString &linkTargetOrName);

signals:
    void changed();

private:
    void refreshSyncParts();
    void requestHyprlandVersion();
    void onHyprlandFinished(int exitCode, QProcess::ExitStatus status);
    void setBusy(bool busy);

    QProcess *m_hyprProcess = nullptr;
    bool m_busy = false;
    QString m_lastError;

    QString m_osPrettyName;
    QString m_osVersion;
    QString m_osId;
    QString m_kernel;
    QString m_hostname;
    QString m_architecture;
    QString m_currentSystemPath;
    QString m_profileSystemPath;
    QString m_profileLinkName;
    int m_profileGeneration = -1;
    bool m_generationPathsMatch = false;
    QString m_generationMatchLabel;
    QString m_hyprlandVersion;
    QString m_sessionType;
    QString m_desktopShell;
    QString m_uptimeLabel;
    QString m_cpuModel;
    QString m_memoryTotalLabel;
    QStringList m_gpuLabels;
    QString m_batterySummary;
};
