#include "PowerModel.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QFile>
#include <QLoggingCategory>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QtMath>

Q_LOGGING_CATEGORY(lcPower, "ryoku.settings.power")

namespace {
constexpr auto kUPowerService = "org.freedesktop.UPower";
constexpr auto kUPowerPath = "/org/freedesktop/UPower";
constexpr auto kDisplayDevice = "/org/freedesktop/UPower/devices/DisplayDevice";
constexpr auto kDeviceIface = "org.freedesktop.UPower.Device";
constexpr auto kPropsIface = "org.freedesktop.DBus.Properties";
constexpr auto kPpdService = "org.freedesktop.UPower.PowerProfiles";
constexpr auto kPpdPath = "/org/freedesktop/UPower/PowerProfiles";
constexpr auto kPpdIface = "org.freedesktop.UPower.PowerProfiles";
constexpr auto kLogin1Service = "org.freedesktop.login1";
constexpr auto kLogin1Path = "/org/freedesktop/login1";
constexpr auto kLogin1Manager = "org.freedesktop.login1.Manager";

QVariant dbusGet(QDBusConnection bus, const QString &service, const QString &path,
                 const QString &iface, const QString &name)
{
    QDBusInterface props(service, path, kPropsIface, bus);
    if (!props.isValid())
        return {};
    const QDBusReply<QVariant> reply = props.call(QStringLiteral("Get"), iface, name);
    if (!reply.isValid())
        return {};
    return reply.value();
}

bool dbusSet(QDBusConnection bus, const QString &service, const QString &path,
             const QString &iface, const QString &name, const QVariant &value, QString *errorOut)
{
    QDBusInterface props(service, path, kPropsIface, bus);
    if (!props.isValid()) {
        if (errorOut)
            *errorOut = QStringLiteral("DBus properties unavailable");
        return false;
    }
    const QDBusMessage reply = props.call(QStringLiteral("Set"), iface, name, QVariant::fromValue(QDBusVariant(value)));
    if (reply.type() == QDBusMessage::ErrorMessage) {
        if (errorOut)
            *errorOut = reply.errorMessage();
        return false;
    }
    return true;
}
} // namespace

PowerModel::PowerModel(QObject *parent)
    : QObject(parent)
{
    m_brightnessDebounce = new QTimer(this);
    m_brightnessDebounce->setSingleShot(true);
    m_brightnessDebounce->setInterval(80);
    connect(m_brightnessDebounce, &QTimer::timeout, this, &PowerModel::applyPendingBrightness);

    m_brightnessctl = findBrightnessctl();
    wireUPowerSignals();
    wireProfileSignals();
    refresh();
}

PowerModel::~PowerModel() = default;

QString PowerModel::findBrightnessctl() const
{
    const QString env = qEnvironmentVariable("RYOKU_BRIGHTNESSCTL");
    if (!env.isEmpty() && QFile::exists(env))
        return env;
    return QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
}

bool PowerModel::runBrightnessctl(const QStringList &args, QByteArray *stdoutOut, QString *errorOut)
{
    if (m_brightnessctl.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("brightnessctl unavailable");
        return false;
    }
    QProcess proc;
    proc.setProgram(m_brightnessctl);
    proc.setArguments(args);
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start();
    if (!proc.waitForFinished(4000)) {
        proc.kill();
        if (errorOut)
            *errorOut = QStringLiteral("brightnessctl timed out");
        return false;
    }
    const QByteArray out = proc.readAll();
    if (stdoutOut)
        *stdoutOut = out;
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        if (errorOut) {
            const QString msg = QString::fromUtf8(out).trimmed();
            *errorOut = msg.isEmpty()
                            ? QStringLiteral("brightnessctl failed")
                            : msg;
        }
        return false;
    }
    return true;
}

void PowerModel::refresh()
{
    refreshBattery();
    refreshBrightness();
    refreshProfiles();
    refreshSleepAndLid();
    emit changed();
}

void PowerModel::wireUPowerSignals()
{
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;

    bus.connect(QString::fromLatin1(kUPowerService), QString::fromLatin1(kDisplayDevice),
                QString::fromLatin1(kPropsIface), QStringLiteral("PropertiesChanged"),
                this, SLOT(onUPowerChanged()));
    bus.connect(QString::fromLatin1(kUPowerService), QString::fromLatin1(kUPowerPath),
                QString::fromLatin1(kUPowerService), QStringLiteral("DeviceChanged"),
                this, SLOT(onUPowerChanged()));
}

void PowerModel::wireProfileSignals()
{
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;
    bus.connect(QString::fromLatin1(kPpdService), QString::fromLatin1(kPpdPath),
                QString::fromLatin1(kPropsIface), QStringLiteral("PropertiesChanged"),
                this, SLOT(onProfilesChanged()));
}

void PowerModel::onUPowerChanged()
{
    refreshBattery();
    emit changed();
}

void PowerModel::onProfilesChanged()
{
    refreshProfiles();
    emit changed();
}

void PowerModel::refreshBattery()
{
    m_batteryError.clear();
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        m_batteryAvailable = false;
        m_batteryPresent = false;
        m_batteryError = QStringLiteral("System DBus unavailable");
        return;
    }

    QDBusInterface upower(kUPowerService, kUPowerPath, kUPowerService, bus);
    if (!upower.isValid()) {
        m_batteryAvailable = false;
        m_batteryPresent = false;
        m_batteryError = QStringLiteral("UPower unavailable");
        return;
    }

    m_batteryAvailable = true;
    const QVariant presentVar = dbusGet(bus, kUPowerService, kDisplayDevice, kDeviceIface, QStringLiteral("IsPresent"));
    m_batteryPresent = presentVar.isValid() && presentVar.toBool();
    if (!m_batteryPresent) {
        m_batteryPercentage = 0.0;
        m_batteryState = QStringLiteral("absent");
        m_batteryStateLabel = QStringLiteral("No battery");
        m_batteryTimeLabel.clear();
        m_energyRateValid = false;
        return;
    }

    const QVariant pct = dbusGet(bus, kUPowerService, kDisplayDevice, kDeviceIface, QStringLiteral("Percentage"));
    m_batteryPercentage = pct.isValid() ? qBound(0.0, pct.toDouble(), 100.0) : 0.0;

    const QVariant stateVar = dbusGet(bus, kUPowerService, kDisplayDevice, kDeviceIface, QStringLiteral("State"));
    const quint32 state = stateVar.isValid() ? stateVar.toUInt() : 0;
    m_batteryState = mapBatteryState(state);
    m_batteryStateLabel = m_batteryState;

    qint64 seconds = -1;
    if (state == 1 || state == 5) { // charging / pending charge
        const QVariant t = dbusGet(bus, kUPowerService, kDisplayDevice, kDeviceIface, QStringLiteral("TimeToFull"));
        if (t.isValid())
            seconds = t.toLongLong();
    } else if (state == 2 || state == 6) {
        const QVariant t = dbusGet(bus, kUPowerService, kDisplayDevice, kDeviceIface, QStringLiteral("TimeToEmpty"));
        if (t.isValid())
            seconds = t.toLongLong();
    }
    m_batteryTimeLabel = formatBatteryTime(seconds);

    const QVariant rate = dbusGet(bus, kUPowerService, kDisplayDevice, kDeviceIface, QStringLiteral("EnergyRate"));
    if (rate.isValid() && rate.toDouble() > 0.0) {
        m_energyRate = rate.toDouble();
        m_energyRateValid = true;
    } else {
        m_energyRate = 0.0;
        m_energyRateValid = false;
    }
}

void PowerModel::refreshBrightness()
{
    m_brightnessError.clear();
    m_brightnessctl = findBrightnessctl();
    if (m_brightnessctl.isEmpty()) {
        m_brightnessAvailable = false;
        m_brightnessError = QStringLiteral("brightnessctl unavailable");
        return;
    }

    QByteArray out;
    QString err;
    // Prefer backlight class so LED indicators are not picked.
    if (!runBrightnessctl({QStringLiteral("-c"), QStringLiteral("backlight"), QStringLiteral("-m"), QStringLiteral("info")},
                          &out, &err)) {
        // Fallback without class filter.
        if (!runBrightnessctl({QStringLiteral("-m"), QStringLiteral("info")}, &out, &err)) {
            m_brightnessAvailable = false;
            m_brightnessError = err;
            return;
        }
    }

    // machine-readable: device,class,value,percent%,max
    const QString line = QString::fromUtf8(out).trimmed().split(QLatin1Char('\n')).value(0);
    const QStringList parts = line.split(QLatin1Char(','));
    if (parts.size() < 4) {
        m_brightnessAvailable = false;
        m_brightnessError = QStringLiteral("Unexpected brightnessctl output");
        return;
    }
    QString pctStr = parts.at(3);
    pctStr.remove(QLatin1Char('%'));
    bool ok = false;
    const int pct = pctStr.toInt(&ok);
    if (!ok) {
        m_brightnessAvailable = false;
        m_brightnessError = QStringLiteral("Could not parse brightness");
        return;
    }
    m_brightness = clampBrightness(pct);
    m_brightnessAvailable = true;
}

void PowerModel::refreshProfiles()
{
    m_profilesError.clear();
    m_profiles.clear();
    m_activeProfile.clear();

    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        m_profilesAvailable = false;
        m_profilesError = QStringLiteral("Power profiles unavailable");
        return;
    }

    QDBusInterface iface(kPpdService, kPpdPath, kPpdIface, bus);
    if (!iface.isValid()) {
        m_profilesAvailable = false;
        m_profilesError = QStringLiteral("Power profiles unavailable");
        return;
    }

    const QVariant active = dbusGet(bus, kPpdService, kPpdPath, kPpdIface, QStringLiteral("ActiveProfile"));
    if (!active.isValid()) {
        m_profilesAvailable = false;
        m_profilesError = QStringLiteral("Power profiles unavailable");
        return;
    }
    m_activeProfile = active.toString();

    const QVariant profilesVar = dbusGet(bus, kPpdService, kPpdPath, kPpdIface, QStringLiteral("Profiles"));
    // Profiles is aa{sv}; Qt may deliver as QDBusArgument. Fallback to known trio if parse hard.
    QStringList ids;
    if (profilesVar.canConvert<QDBusArgument>()) {
        const QDBusArgument arg = profilesVar.value<QDBusArgument>();
        arg.beginArray();
        while (!arg.atEnd()) {
            arg.beginMap();
            QString profileId;
            while (!arg.atEnd()) {
                QString key;
                QVariant val;
                arg.beginMapEntry();
                arg >> key >> val;
                arg.endMapEntry();
                if (key == QLatin1String("Profile"))
                    profileId = val.toString();
            }
            arg.endMap();
            if (!profileId.isEmpty())
                ids.append(profileId);
        }
        arg.endArray();
    }

    if (ids.isEmpty()) {
        // Safe known set if daemon is up but argument unpacking differs.
        ids = {QStringLiteral("power-saver"), QStringLiteral("balanced"), QStringLiteral("performance")};
    }

    for (const QString &id : ids) {
        QVariantMap row;
        row.insert(QStringLiteral("id"), id);
        row.insert(QStringLiteral("name"), profileDisplayName(id));
        row.insert(QStringLiteral("active"), id == m_activeProfile);
        m_profiles.append(row);
    }
    m_profilesAvailable = true;
}

void PowerModel::refreshSleepAndLid()
{
    // Read-only hints. Prefer logind when reachable; otherwise show declarative Ryoku defaults.
    m_lidBehaviorLabel = QStringLiteral("Ignore (declarative)");
    m_suspendLabel = QStringLiteral("System default (declarative)");
    m_idleLabel = QStringLiteral("hypridle installed (declarative)");

    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected())
        return;

    QDBusInterface login(kLogin1Service, kLogin1Path, kLogin1Manager, bus);
    if (!login.isValid())
        return;

    // logind exposes IdleAction / IdleActionUSec but not HandleLidSwitch over DBus on most systems.
    const QVariant idleAction = dbusGet(bus, kLogin1Service, kLogin1Path, kLogin1Manager, QStringLiteral("IdleAction"));
    if (idleAction.isValid()) {
        const QString action = idleAction.toString();
        if (!action.isEmpty())
            m_suspendLabel = QStringLiteral("Idle action: %1").arg(action);
    }
}

QStringList PowerModel::brightnessSetArgs(int percent, bool withBacklightClass)
{
    // brightnessctl 0.5: -n/--min-value is a FLAG (defaults to 1). It does NOT
    // take a separate "1" argument — passing `-n 1 set 70%` makes `1` consume
    // the operation slot so `set` never runs (exit 0, no hardware change).
    const int clamped = clampBrightness(percent);
    QStringList args;
    if (withBacklightClass)
        args << QStringLiteral("-c") << QStringLiteral("backlight");
    args << QStringLiteral("-n")
         << QStringLiteral("set")
         << QStringLiteral("%1%").arg(clamped);
    return args;
}

void PowerModel::setBrightness(int percent)
{
    const int clamped = clampBrightness(percent);
    m_pendingBrightness = -1;
    QString err;
    // Prefer class=backlight so keyboard LEDs are never selected.
    if (!runBrightnessctl(brightnessSetArgs(clamped, true), nullptr, &err)) {
        if (!runBrightnessctl(brightnessSetArgs(clamped, false), nullptr, &err)) {
            m_brightnessError = err;
            emit operationFailed(err);
            emit changed();
            return;
        }
    }
    m_brightnessError.clear();
    m_brightness = clamped;
    emit changed();
}

void PowerModel::scheduleBrightness(int percent)
{
    m_pendingBrightness = clampBrightness(percent);
    m_brightness = m_pendingBrightness; // optimistic UI
    emit changed();
    m_brightnessDebounce->start();
}

void PowerModel::applyPendingBrightness()
{
    if (m_pendingBrightness < 0)
        return;
    const int value = m_pendingBrightness;
    m_pendingBrightness = -1;
    setBrightness(value);
}

void PowerModel::setPowerProfile(const QString &profile)
{
    if (!m_profilesAvailable) {
        emit operationFailed(QStringLiteral("Power profiles unavailable"));
        return;
    }
    QString err;
    if (!dbusSet(QDBusConnection::systemBus(), kPpdService, kPpdPath, kPpdIface,
                 QStringLiteral("ActiveProfile"), profile, &err)) {
        emit operationFailed(err.isEmpty() ? QStringLiteral("Failed to set power profile") : err);
        return;
    }
    refreshProfiles();
    emit changed();
}

int PowerModel::clampBrightness(int percent)
{
    return qBound(1, percent, 100);
}

QString PowerModel::mapBatteryState(quint32 state)
{
    switch (state) {
    case 1:
        return QStringLiteral("Charging");
    case 2:
        return QStringLiteral("Discharging");
    case 3:
        return QStringLiteral("Empty");
    case 4:
        return QStringLiteral("Full");
    case 5:
        return QStringLiteral("Pending charge");
    case 6:
        return QStringLiteral("Pending discharge");
    default:
        return QStringLiteral("Unknown");
    }
}

QString PowerModel::formatBatteryTime(qint64 seconds)
{
    if (seconds <= 0)
        return {};
    const qint64 hours = seconds / 3600;
    const qint64 mins = (seconds % 3600) / 60;
    if (hours > 0)
        return QStringLiteral("%1h %2m").arg(hours).arg(mins);
    return QStringLiteral("%1m").arg(mins);
}

QString PowerModel::mapProfileId(const QString &id)
{
    return id.trimmed().toLower();
}

QString PowerModel::profileDisplayName(const QString &id)
{
    const QString key = mapProfileId(id);
    if (key == QLatin1String("performance"))
        return QStringLiteral("Performance");
    if (key == QLatin1String("balanced"))
        return QStringLiteral("Balanced");
    if (key == QLatin1String("power-saver") || key == QLatin1String("power_saver"))
        return QStringLiteral("Power Saver");
    return id;
}
