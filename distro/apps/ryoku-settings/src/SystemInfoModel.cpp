#include "SystemInfoModel.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSysInfo>
#include <QLoggingCategory>

#include <algorithm>

Q_LOGGING_CATEGORY(lcSystemInfo, "ryoku.settings.system")

namespace {
QByteArray readFileBytes(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}
} // namespace

SystemInfoModel::SystemInfoModel(QObject *parent)
    : QObject(parent)
{
    m_desktopShell = QStringLiteral("DMS / Ryoku");
}

SystemInfoModel::~SystemInfoModel()
{
    if (m_hyprProcess) {
        m_hyprProcess->kill();
        m_hyprProcess->waitForFinished(500);
    }
}

QString SystemInfoModel::canonicalPathOrEmpty(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.exists())
        return {};
    const QString canon = fi.canonicalFilePath();
    return canon.isEmpty() ? fi.absoluteFilePath() : canon;
}

int SystemInfoModel::parseProfileGeneration(const QString &linkTargetOrName)
{
    static const QRegularExpression re(QStringLiteral("(?:^|/)system-(\\d+)-link(?:$|/)"));
    const auto m = re.match(linkTargetOrName);
    if (!m.hasMatch())
        return -1;
    bool ok = false;
    const int gen = m.captured(1).toInt(&ok);
    return ok ? gen : -1;
}

bool SystemInfoModel::pathsMatch(const QString &a, const QString &b)
{
    if (a.isEmpty() || b.isEmpty())
        return false;
    return a == b;
}

QString SystemInfoModel::generationMatchLabelFor(bool bothPresent, bool match)
{
    if (!bothPresent)
        return QStringLiteral("Generation paths unavailable");
    if (match)
        return QStringLiteral("Active generation matches system profile");
    return QStringLiteral("Current system differs from system profile");
}

QString SystemInfoModel::pickOsReleasePath()
{
    const QStringList candidates{
        QStringLiteral("/run/current-system/etc/os-release"),
        QStringLiteral("/nix/var/nix/profiles/system/etc/os-release"),
        QStringLiteral("/etc/os-release"),
    };
    QString fallback;
    for (const QString &path : candidates) {
        const QByteArray raw = readFileBytes(path);
        if (raw.isEmpty())
            continue;
        if (fallback.isEmpty())
            fallback = path;
        const QVariantMap m = parseOsRelease(raw);
        if (m.value(QStringLiteral("ID")).toString() == QLatin1String("nixos"))
            return path;
    }
    return fallback.isEmpty() ? QStringLiteral("/etc/os-release") : fallback;
}

QVariantMap SystemInfoModel::parseOsRelease(const QByteArray &text)
{
    QVariantMap out;
    const QList<QByteArray> lines = text.split('\n');
    for (QByteArray line : lines) {
        line = line.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        const int eq = line.indexOf('=');
        if (eq <= 0)
            continue;
        QByteArray key = line.left(eq).trimmed();
        QByteArray val = line.mid(eq + 1).trimmed();
        if (val.size() >= 2 && val.startsWith('"') && val.endsWith('"'))
            val = val.mid(1, val.size() - 2);
        out.insert(QString::fromUtf8(key), QString::fromUtf8(val));
    }
    return out;
}

QString SystemInfoModel::parseCpuModel(const QByteArray &cpuinfo)
{
    static const QRegularExpression re(QStringLiteral("^model name\\s*:\\s*(.+)$"),
                                       QRegularExpression::MultilineOption);
    const auto m = re.match(QString::fromUtf8(cpuinfo));
    if (m.hasMatch())
        return m.captured(1).trimmed();
    return {};
}

qint64 SystemInfoModel::parseMemTotalKb(const QByteArray &meminfo)
{
    static const QRegularExpression re(QStringLiteral("^MemTotal:\\s*(\\d+)\\s*kB"),
                                       QRegularExpression::MultilineOption);
    const auto m = re.match(QString::fromUtf8(meminfo));
    if (!m.hasMatch())
        return -1;
    bool ok = false;
    const qint64 v = m.captured(1).toLongLong(&ok);
    return ok ? v : -1;
}

QString SystemInfoModel::formatMemoryFromKb(qint64 kb)
{
    if (kb < 0)
        return QStringLiteral("Unavailable");
    const double gib = static_cast<double>(kb) / (1024.0 * 1024.0);
    return QStringLiteral("%1 GiB").arg(gib, 0, 'f', 1);
}

QString SystemInfoModel::formatUptime(double seconds)
{
    if (seconds < 0)
        return QStringLiteral("Unavailable");
    const qint64 total = static_cast<qint64>(seconds);
    const qint64 days = total / 86400;
    const qint64 hours = (total % 86400) / 3600;
    const qint64 mins = (total % 3600) / 60;
    if (days > 0)
        return QStringLiteral("%1d %2h %3m").arg(days).arg(hours).arg(mins);
    if (hours > 0)
        return QStringLiteral("%1h %2m").arg(hours).arg(mins);
    return QStringLiteral("%1m").arg(mins);
}

QString SystemInfoModel::parseHyprctlVersionLine(const QByteArray &output)
{
    const QString text = QString::fromUtf8(output).trimmed();
    if (text.isEmpty())
        return {};
    const QString first = text.split(QLatin1Char('\n')).value(0).trimmed();
    // "Hyprland 0.56.2 built from branch ..."
    static const QRegularExpression re(QStringLiteral("^Hyprland\\s+(\\S+)"));
    const auto m = re.match(first);
    if (m.hasMatch())
        return m.captured(1);
    return first.left(80);
}

QStringList SystemInfoModel::parseDrmGpuLabels(const QStringList &drmEntries)
{
    QStringList out;
    for (const QString &e : drmEntries) {
        if (!e.startsWith(QLatin1String("card")) || e.contains(QLatin1Char('-')))
            continue;
        out.append(e);
    }
    out.removeDuplicates();
    std::sort(out.begin(), out.end());
    return out;
}

QStringList SystemInfoModel::gpuLabelsFromSysfs()
{
    QStringList out;
    const QDir drm(QStringLiteral("/sys/class/drm"));
    const QStringList entries = drm.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &e : parseDrmGpuLabels(entries)) {
        const QString ueventPath =
            drm.filePath(e + QStringLiteral("/device/uevent"));
        const QByteArray uevent = readFileBytes(ueventPath);
        QString driver;
        QString pciId;
        for (const QByteArray &line : uevent.split('\n')) {
            if (line.startsWith("DRIVER="))
                driver = QString::fromUtf8(line.mid(7));
            else if (line.startsWith("PCI_ID="))
                pciId = QString::fromUtf8(line.mid(7));
        }
        if (!driver.isEmpty() && !pciId.isEmpty())
            out.append(QStringLiteral("%1 (%2)").arg(driver, pciId));
        else if (!driver.isEmpty())
            out.append(driver);
        else
            out.append(e);
    }
    return out;
}

void SystemInfoModel::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
}

void SystemInfoModel::refresh()
{
    m_lastError.clear();
    refreshSyncParts();
    requestHyprlandVersion();
    emit changed();
}

void SystemInfoModel::refreshSyncParts()
{
    const QString osPath = pickOsReleasePath();
    const QVariantMap os = parseOsRelease(readFileBytes(osPath));
    m_osPrettyName = os.value(QStringLiteral("PRETTY_NAME")).toString();
    m_osVersion = os.value(QStringLiteral("VERSION")).toString();
    if (m_osVersion.isEmpty())
        m_osVersion = os.value(QStringLiteral("BUILD_ID")).toString();
    m_osId = os.value(QStringLiteral("ID")).toString();
    if (m_osPrettyName.isEmpty())
        m_osPrettyName = QStringLiteral("Unavailable");

    m_kernel = QSysInfo::kernelVersion();
    if (m_kernel.isEmpty())
        m_kernel = QStringLiteral("Unavailable");

    m_hostname = QHostInfo::localHostName();
    if (m_hostname.isEmpty())
        m_hostname = QStringLiteral("Unavailable");

    m_architecture = QSysInfo::currentCpuArchitecture();
    if (m_architecture.isEmpty())
        m_architecture = QStringLiteral("Unavailable");

    m_currentSystemPath = canonicalPathOrEmpty(QStringLiteral("/run/current-system"));
    m_profileSystemPath = canonicalPathOrEmpty(QStringLiteral("/nix/var/nix/profiles/system"));
    {
        const QFileInfo profileFi(QStringLiteral("/nix/var/nix/profiles/system"));
        m_profileLinkName = profileFi.symLinkTarget();
        if (m_profileLinkName.isEmpty())
            m_profileLinkName = profileFi.fileName();
        m_profileGeneration = parseProfileGeneration(m_profileLinkName);
        if (m_profileGeneration < 0)
            m_profileGeneration = parseProfileGeneration(profileFi.filePath());
    }
    const bool both = !m_currentSystemPath.isEmpty() && !m_profileSystemPath.isEmpty();
    m_generationPathsMatch = pathsMatch(m_currentSystemPath, m_profileSystemPath);
    m_generationMatchLabel = generationMatchLabelFor(both, m_generationPathsMatch);

    const QString xdg = qEnvironmentVariable("XDG_SESSION_TYPE");
    m_sessionType = xdg.isEmpty()
                        ? (qEnvironmentVariableIsSet("WAYLAND_DISPLAY")
                               ? QStringLiteral("wayland")
                               : QStringLiteral("Unavailable"))
                        : xdg;

    const QByteArray uptimeRaw = readFileBytes(QStringLiteral("/proc/uptime"));
    bool okUptime = false;
    const double upSecs = QString::fromUtf8(uptimeRaw).section(QLatin1Char(' '), 0, 0).toDouble(&okUptime);
    m_uptimeLabel = okUptime ? formatUptime(upSecs) : QStringLiteral("Unavailable");

    m_cpuModel = parseCpuModel(readFileBytes(QStringLiteral("/proc/cpuinfo")));
    if (m_cpuModel.isEmpty())
        m_cpuModel = QStringLiteral("Unavailable");

    m_memoryTotalLabel = formatMemoryFromKb(parseMemTotalKb(readFileBytes(QStringLiteral("/proc/meminfo"))));

    m_gpuLabels = gpuLabelsFromSysfs();
    if (m_gpuLabels.isEmpty())
        m_gpuLabels = {QStringLiteral("Unavailable")};

    // Lightweight battery presence via /sys — detailed status stays on Power page.
    const QDir power(QStringLiteral("/sys/class/power_supply"));
    const QStringList supplies = power.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    bool hasBattery = false;
    QString status;
    for (const QString &name : supplies) {
        const QByteArray type = readFileBytes(power.filePath(name + QStringLiteral("/type"))).trimmed();
        if (type != "Battery")
            continue;
        hasBattery = true;
        status = QString::fromUtf8(
            readFileBytes(power.filePath(name + QStringLiteral("/status"))).trimmed());
        const QByteArray cap =
            readFileBytes(power.filePath(name + QStringLiteral("/capacity"))).trimmed();
        if (!cap.isEmpty())
            m_batterySummary = QStringLiteral("%1% · %2")
                                   .arg(QString::fromUtf8(cap),
                                        status.isEmpty() ? QStringLiteral("Battery") : status);
        else
            m_batterySummary = status.isEmpty() ? QStringLiteral("Present") : status;
        break;
    }
    if (!hasBattery)
        m_batterySummary = QStringLiteral("No battery");
}

void SystemInfoModel::requestHyprlandVersion()
{
    if (!m_hyprProcess) {
        m_hyprProcess = new QProcess(this);
        connect(m_hyprProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &SystemInfoModel::onHyprlandFinished);
    }
    if (m_hyprProcess->state() != QProcess::NotRunning)
        return;

    setBusy(true);
    m_hyprlandVersion = QStringLiteral("…");
    emit changed();

    m_hyprProcess->setProgram(QStringLiteral("hyprctl"));
    m_hyprProcess->setArguments({QStringLiteral("version")});
    m_hyprProcess->setProcessChannelMode(QProcess::SeparateChannels);
    m_hyprProcess->start();
}

void SystemInfoModel::onHyprlandFinished(int exitCode, QProcess::ExitStatus status)
{
    setBusy(false);
    if (!m_hyprProcess)
        return;
    const QByteArray out = m_hyprProcess->readAllStandardOutput();
    const QByteArray err = m_hyprProcess->readAllStandardError();
    if (status != QProcess::NormalExit || exitCode != 0) {
        m_hyprlandVersion = QStringLiteral("Unavailable");
        if (!err.isEmpty())
            m_lastError = QString::fromUtf8(err).trimmed().left(200);
        qWarning(lcSystemInfo) << "hyprctl version failed" << exitCode << err;
    } else {
        m_hyprlandVersion = parseHyprctlVersionLine(out);
        if (m_hyprlandVersion.isEmpty())
            m_hyprlandVersion = QStringLiteral("Unavailable");
    }
    emit changed();
}
