#include "NetworkManagerModel.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusVariant>
#include <QLoggingCategory>
#include <algorithm>

Q_LOGGING_CATEGORY(lcNm, "ryoku.settings.network")

namespace {
constexpr auto kNmService = "org.freedesktop.NetworkManager";
constexpr auto kNmPath = "/org/freedesktop/NetworkManager";
constexpr auto kNmIface = "org.freedesktop.NetworkManager";
constexpr auto kPropsIface = "org.freedesktop.DBus.Properties";
constexpr auto kWifiIface = "org.freedesktop.NetworkManager.Device.Wireless";
constexpr auto kDeviceIface = "org.freedesktop.NetworkManager.Device";
constexpr auto kApIface = "org.freedesktop.NetworkManager.AccessPoint";
constexpr auto kSettingsPath = "/org/freedesktop/NetworkManager/Settings";
constexpr auto kSettingsIface = "org.freedesktop.NetworkManager.Settings";
constexpr auto kConnIface = "org.freedesktop.NetworkManager.Settings.Connection";

QVariant dbusProp(QDBusConnection bus, const QString &path, const QString &iface, const QString &name)
{
    QDBusInterface props(kNmService, path, kPropsIface, bus);
    if (!props.isValid())
        return {};
    const QDBusReply<QVariant> reply = props.call(QStringLiteral("Get"), iface, name);
    if (!reply.isValid())
        return {};
    return reply.value();
}

QString pathStr(const QVariant &v)
{
    if (v.canConvert<QDBusObjectPath>())
        return v.value<QDBusObjectPath>().path();
    return v.toString();
}
} // namespace

NetworkManagerModel::NetworkManagerModel(QObject *parent)
    : QAbstractListModel(parent)
{
    ensureService();
    if (m_available) {
        wireSignals();
        refresh();
    }
}

NetworkManagerModel::~NetworkManagerModel() = default;

int NetworkManagerModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_aps.size();
}

QVariant NetworkManagerModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_aps.size())
        return {};
    const AccessPoint &ap = m_aps.at(index.row());
    switch (role) {
    case SsidRole:
        return ap.ssid;
    case StrengthRole:
        return ap.strength;
    case SecuredRole:
        return ap.secured;
    case SecurityLabelRole:
        return securityLabel(ap.secured);
    case ConnectedRole:
        return ap.connected;
    case BssidRole:
        return ap.bssid;
    case PathRole:
        return ap.path;
    default:
        return {};
    }
}

QHash<int, QByteArray> NetworkManagerModel::roleNames() const
{
    return {
        {SsidRole, "ssid"},
        {StrengthRole, "strength"},
        {SecuredRole, "secured"},
        {SecurityLabelRole, "securityLabel"},
        {ConnectedRole, "connected"},
        {BssidRole, "bssid"},
        {PathRole, "path"},
    };
}

QString NetworkManagerModel::securityLabel(bool secured)
{
    return secured ? QCoreApplication::translate("NetworkManagerModel", "Secured")
                   : QCoreApplication::translate("NetworkManagerModel", "Open");
}

void NetworkManagerModel::retranslateUi()
{
    // Re-read labels through tr(); DBus state unchanged.
    if (m_available)
        reloadDevices();
    if (rowCount() > 0)
        emit dataChanged(index(0), index(rowCount() - 1));
    emit changed();
}

int NetworkManagerModel::clampStrength(int strength)
{
    return qBound(0, strength, 100);
}

bool NetworkManagerModel::isSecuredFromFlags(quint32 /*flags*/, quint32 wpa, quint32 rsn)
{
    return wpa != 0 || rsn != 0;
}

QVector<NetworkManagerModel::AccessPoint> NetworkManagerModel::sortAccessPoints(QVector<AccessPoint> aps)
{
    std::sort(aps.begin(), aps.end(), [](const AccessPoint &a, const AccessPoint &b) {
        if (a.connected != b.connected)
            return a.connected && !b.connected;
        if (a.strength != b.strength)
            return a.strength > b.strength;
        return a.ssid.localeAwareCompare(b.ssid) < 0;
    });
    return aps;
}

void NetworkManagerModel::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void NetworkManagerModel::setError(const QString &err)
{
    m_error = err;
}

bool NetworkManagerModel::ensureService()
{
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        m_available = false;
        setError(QStringLiteral("System DBus unavailable"));
        m_connectivityLabel = tr("Unavailable");
        emit changed();
        return false;
    }

    QDBusInterface nm(kNmService, kNmPath, kNmIface, bus);
    if (!nm.isValid()) {
        m_available = false;
        setError(QStringLiteral("NetworkManager unavailable"));
        m_connectivityLabel = tr("Unavailable");
        emit changed();
        return false;
    }

    m_available = true;
    setError({});
    return true;
}

void NetworkManagerModel::wireSignals()
{
    if (m_signalsWired)
        return;
    auto bus = QDBusConnection::systemBus();
    bus.connect(kNmService, kNmPath, kPropsIface, QStringLiteral("PropertiesChanged"),
                this, SLOT(onNmEvent()));
    bus.connect(kNmService, QString(), kWifiIface, QStringLiteral("AccessPointAdded"),
                this, SLOT(onNmEvent()));
    bus.connect(kNmService, QString(), kWifiIface, QStringLiteral("AccessPointRemoved"),
                this, SLOT(onNmEvent()));
    bus.connect(kNmService, QString(), kDeviceIface, QStringLiteral("StateChanged"),
                this, SLOT(onNmEvent()));
    m_signalsWired = true;
}

void NetworkManagerModel::onNmEvent()
{
    refresh();
}

void NetworkManagerModel::refresh()
{
    if (!ensureService())
        return;
    reloadDevices();
    reloadActiveConnection();
    reloadAccessPoints();
    emit changed();
}

void NetworkManagerModel::reloadDevices()
{
    auto bus = QDBusConnection::systemBus();
    m_wifiEnabled = dbusProp(bus, kNmPath, kNmIface, QStringLiteral("WirelessEnabled")).toBool();
    const QVariant hw = dbusProp(bus, kNmPath, kNmIface, QStringLiteral("WirelessHardwareEnabled"));
    m_wifiHw = hw.isValid() ? hw.toBool() : true;

    const int state = dbusProp(bus, kNmPath, kNmIface, QStringLiteral("State")).toInt();
    if (state >= 70)
        m_connectivityLabel = tr("Connected");
    else if (state >= 50)
        m_connectivityLabel = tr("Limited");
    else if (state >= 20)
        m_connectivityLabel = tr("Connecting");
    else
        m_connectivityLabel = tr("Offline");

    QDBusInterface nm(kNmService, kNmPath, kNmIface, bus);
    const QDBusReply<QList<QDBusObjectPath>> devices = nm.call(QStringLiteral("GetDevices"));
    m_wifiDevicePath.clear();
    m_ethernetLabel = tr("Not present");
    m_primaryDevice.clear();
    if (!devices.isValid())
        return;

    for (const QDBusObjectPath &devPath : devices.value()) {
        const int type = dbusProp(bus, devPath.path(), kDeviceIface, QStringLiteral("DeviceType")).toInt();
        const QString iface = dbusProp(bus, devPath.path(), kDeviceIface, QStringLiteral("Interface")).toString();
        const int devState = dbusProp(bus, devPath.path(), kDeviceIface, QStringLiteral("State")).toInt();
        if (type == 2 && m_wifiDevicePath.isEmpty()) {
            m_wifiDevicePath = devPath.path();
            m_primaryDevice = iface;
        } else if (type == 1) {
            m_ethernetLabel = (devState >= 100)
                                  ? tr("Connected (%1)").arg(iface)
                                  : tr("Present (%1)").arg(iface);
            if (m_primaryDevice.isEmpty())
                m_primaryDevice = iface;
        }
    }
    if (m_wifiDevicePath.isEmpty())
        m_wifiHw = false;
}

void NetworkManagerModel::reloadActiveConnection()
{
    auto bus = QDBusConnection::systemBus();
    m_connectedSsid.clear();
    m_connectedStrength = 0;
    m_activeApPath.clear();
    if (m_wifiDevicePath.isEmpty())
        return;

    m_activeApPath = pathStr(dbusProp(bus, m_wifiDevicePath, kWifiIface, QStringLiteral("ActiveAccessPoint")));
    if (m_activeApPath.isEmpty() || m_activeApPath == QLatin1String("/"))
        return;

    const QByteArray ssidRaw = dbusProp(bus, m_activeApPath, kApIface, QStringLiteral("Ssid")).toByteArray();
    m_connectedSsid = QString::fromUtf8(ssidRaw);
    m_connectedStrength = clampStrength(dbusProp(bus, m_activeApPath, kApIface, QStringLiteral("Strength")).toInt());
}

void NetworkManagerModel::reloadAccessPoints()
{
    auto bus = QDBusConnection::systemBus();
    QVector<AccessPoint> next;
    if (!m_wifiDevicePath.isEmpty() && m_wifiEnabled) {
        QDBusInterface wifi(kNmService, m_wifiDevicePath, kWifiIface, bus);
        const QDBusReply<QList<QDBusObjectPath>> aps = wifi.call(QStringLiteral("GetAccessPoints"));
        if (aps.isValid()) {
            QHash<QString, int> bestBySsid;
            QHash<QString, AccessPoint> bySsid;
            for (const QDBusObjectPath &apPath : aps.value()) {
                AccessPoint ap;
                ap.path = apPath.path();
                const QByteArray ssidRaw = dbusProp(bus, ap.path, kApIface, QStringLiteral("Ssid")).toByteArray();
                ap.ssid = QString::fromUtf8(ssidRaw);
                if (ap.ssid.isEmpty())
                    continue;
                ap.bssid = dbusProp(bus, ap.path, kApIface, QStringLiteral("HwAddress")).toString();
                ap.strength = clampStrength(dbusProp(bus, ap.path, kApIface, QStringLiteral("Strength")).toInt());
                const quint32 flags = dbusProp(bus, ap.path, kApIface, QStringLiteral("Flags")).toUInt();
                const quint32 wpa = dbusProp(bus, ap.path, kApIface, QStringLiteral("WpaFlags")).toUInt();
                const quint32 rsn = dbusProp(bus, ap.path, kApIface, QStringLiteral("RsnFlags")).toUInt();
                ap.secured = isSecuredFromFlags(flags, wpa, rsn);
                ap.connected = (ap.path == m_activeApPath) || (ap.ssid == m_connectedSsid && !m_connectedSsid.isEmpty());

                if (!bySsid.contains(ap.ssid) || ap.strength > bestBySsid.value(ap.ssid)) {
                    bySsid.insert(ap.ssid, ap);
                    bestBySsid.insert(ap.ssid, ap.strength);
                }
            }
            next = bySsid.values().toVector();
        }
    }
    next = sortAccessPoints(next);

    beginResetModel();
    m_aps = next;
    endResetModel();
}

void NetworkManagerModel::requestScan()
{
    if (!ensureService() || m_wifiDevicePath.isEmpty()) {
        emit operationFailed(QStringLiteral("Wi-Fi device unavailable"));
        return;
    }
    auto bus = QDBusConnection::systemBus();
    QDBusInterface wifi(kNmService, m_wifiDevicePath, kWifiIface, bus);
    const QDBusReply<void> reply = wifi.call(QStringLiteral("RequestScan"), QVariantMap());
    if (!reply.isValid()) {
        const QString msg = reply.error().message();
        setError(msg);
        emit operationFailed(msg.isEmpty() ? QStringLiteral("Scan failed") : msg);
        emit changed();
        return;
    }
    // Results arrive via AccessPointAdded / PropertiesChanged → refresh().
}

void NetworkManagerModel::setWifiEnabled(bool enabled)
{
    if (!ensureService())
        return;
    setBusy(true);
    auto bus = QDBusConnection::systemBus();
    QDBusInterface props(kNmService, kNmPath, kPropsIface, bus);
    const QDBusReply<void> reply = props.call(QStringLiteral("Set"),
                                              QString(kNmIface),
                                              QStringLiteral("WirelessEnabled"),
                                              QVariant::fromValue(QDBusVariant(enabled)));
    setBusy(false);
    if (!reply.isValid()) {
        const QString msg = reply.error().message();
        setError(msg);
        emit operationFailed(msg.isEmpty() ? QStringLiteral("Failed to toggle Wi-Fi") : msg);
    }
    refresh();
}

void NetworkManagerModel::disconnectWifi()
{
    if (!ensureService())
        return;
    auto bus = QDBusConnection::systemBus();
    const QString active = pathStr(dbusProp(bus, kNmPath, kNmIface, QStringLiteral("PrimaryConnection")));
    if (active.isEmpty() || active == QLatin1String("/")) {
        // Fallback: deactivate device's ActiveConnection
        if (!m_wifiDevicePath.isEmpty()) {
            const QString ac = pathStr(dbusProp(bus, m_wifiDevicePath, kDeviceIface, QStringLiteral("ActiveConnection")));
            if (!ac.isEmpty() && ac != QLatin1String("/")) {
                QDBusInterface nm(kNmService, kNmPath, kNmIface, bus);
                nm.call(QStringLiteral("DeactivateConnection"), QVariant::fromValue(QDBusObjectPath(ac)));
            }
        }
        refresh();
        return;
    }
    QDBusInterface nm(kNmService, kNmPath, kNmIface, bus);
    const QDBusReply<void> reply = nm.call(QStringLiteral("DeactivateConnection"),
                                           QVariant::fromValue(QDBusObjectPath(active)));
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    refresh();
}

QString NetworkManagerModel::findWifiDevicePath() const
{
    return m_wifiDevicePath;
}

QByteArray NetworkManagerModel::ssidBytes(const QString &ssid) const
{
    return ssid.toUtf8();
}

QString NetworkManagerModel::findKnownConnectionPath(const QString &ssid) const
{
    auto bus = QDBusConnection::systemBus();
    QDBusInterface settings(kNmService, kSettingsPath, kSettingsIface, bus);
    const QDBusReply<QList<QDBusObjectPath>> list = settings.call(QStringLiteral("ListConnections"));
    if (!list.isValid())
        return {};

    const QByteArray want = ssid.toUtf8();
    for (const QDBusObjectPath &cpath : list.value()) {
        QDBusInterface conn(kNmService, cpath.path(), kConnIface, bus);
        const QDBusReply<QVariantMap> settingsReply = conn.call(QStringLiteral("GetSettings"));
        // GetSettings returns a{sa{sv}} — QDBus maps it poorly as QVariantMap of QDBusArgument.
        // Use raw message for robust parse:
        QDBusMessage msg = QDBusMessage::createMethodCall(kNmService, cpath.path(), kConnIface, QStringLiteral("GetSettings"));
        const QDBusMessage response = bus.call(msg);
        if (response.type() != QDBusMessage::ReplyMessage || response.arguments().isEmpty())
            continue;
        const QDBusArgument arg = response.arguments().first().value<QDBusArgument>();
        if (arg.currentType() != QDBusArgument::MapType)
            continue;
        arg.beginMap();
        while (!arg.atEnd()) {
            QString key;
            QVariantMap map;
            arg.beginMapEntry();
            arg >> key >> map;
            arg.endMapEntry();
            if (key == QLatin1String("802-11-wireless") && map.value(QStringLiteral("ssid")).toByteArray() == want)
                return cpath.path();
        }
        arg.endMap();
    }
    return {};
}

void NetworkManagerModel::connectToNetwork(const QString &ssid, const QString &password)
{
    if (!ensureService() || m_wifiDevicePath.isEmpty()) {
        emit operationFailed(QStringLiteral("Wi-Fi device unavailable"));
        return;
    }
    if (ssid.isEmpty()) {
        emit operationFailed(QStringLiteral("Invalid SSID"));
        return;
    }

    // Find AP row for security + path
    AccessPoint match;
    for (const AccessPoint &ap : m_aps) {
        if (ap.ssid == ssid) {
            match = ap;
            break;
        }
    }

    if (match.secured && password.isEmpty()) {
        const QString known = findKnownConnectionPath(ssid);
        if (known.isEmpty()) {
            emit passwordRequired(ssid);
            return;
        }
    }

    setBusy(true);
    auto bus = QDBusConnection::systemBus();
    QDBusInterface nm(kNmService, kNmPath, kNmIface, bus);

    // Prefer activating an existing saved profile.
    const QString known = findKnownConnectionPath(ssid);
    if (!known.isEmpty() && password.isEmpty()) {
        const QDBusReply<QDBusObjectPath> reply = nm.call(
            QStringLiteral("ActivateConnection"),
            QVariant::fromValue(QDBusObjectPath(known)),
            QVariant::fromValue(QDBusObjectPath(m_wifiDevicePath)),
            QVariant::fromValue(QDBusObjectPath(match.path.isEmpty() ? QStringLiteral("/") : match.path)));
        setBusy(false);
        if (!reply.isValid()) {
            emit operationFailed(reply.error().message());
            refresh();
            return;
        }
        refresh();
        return;
    }

    if (match.secured && password.isEmpty()) {
        setBusy(false);
        emit passwordRequired(ssid);
        return;
    }

    // Build ephemeral connection settings for AddAndActivateConnection (a{sa{sv}}).
    QMap<QString, QVariantMap> root;
    QVariantMap wireless;
    wireless.insert(QStringLiteral("ssid"), QVariant(ssidBytes(ssid)));
    wireless.insert(QStringLiteral("mode"), QStringLiteral("infrastructure"));

    QVariantMap conn;
    conn.insert(QStringLiteral("id"), ssid);
    conn.insert(QStringLiteral("type"), QStringLiteral("802-11-wireless"));

    QVariantMap ipv4;
    ipv4.insert(QStringLiteral("method"), QStringLiteral("auto"));
    QVariantMap ipv6;
    ipv6.insert(QStringLiteral("method"), QStringLiteral("auto"));

    root.insert(QStringLiteral("connection"), conn);
    root.insert(QStringLiteral("802-11-wireless"), wireless);
    root.insert(QStringLiteral("ipv4"), ipv4);
    root.insert(QStringLiteral("ipv6"), ipv6);

    if (match.secured || !password.isEmpty()) {
        QVariantMap sec;
        sec.insert(QStringLiteral("key-mgmt"), QStringLiteral("wpa-psk"));
        sec.insert(QStringLiteral("psk"), password);
        root.insert(QStringLiteral("802-11-wireless-security"), sec);
    }

    qDBusRegisterMetaType<QMap<QString, QVariantMap>>();
    QDBusMessage msg = QDBusMessage::createMethodCall(
        kNmService, kNmPath, kNmIface, QStringLiteral("AddAndActivateConnection"));
    msg << QVariant::fromValue(root)
        << QVariant::fromValue(QDBusObjectPath(m_wifiDevicePath))
        << QVariant::fromValue(QDBusObjectPath(match.path.isEmpty() ? QStringLiteral("/") : match.path));
    const QDBusMessage response = bus.call(msg);

    setBusy(false);
    if (response.type() == QDBusMessage::ErrorMessage) {
        const QString msgText = response.errorMessage();
        qWarning(lcNm) << "connect failed for SSID" << ssid << msgText;
        emit operationFailed(msgText.isEmpty() ? QStringLiteral("Connection failed") : msgText);
    }
    refresh();
}
