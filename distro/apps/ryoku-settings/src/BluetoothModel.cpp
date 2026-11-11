#include "BluetoothModel.h"

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

Q_LOGGING_CATEGORY(lcBt, "ryoku.settings.bluetooth")

namespace {
constexpr auto kBluez = "org.bluez";
constexpr auto kOmIface = "org.freedesktop.DBus.ObjectManager";
constexpr auto kPropsIface = "org.freedesktop.DBus.Properties";
constexpr auto kAdapterIface = "org.bluez.Adapter1";
constexpr auto kDeviceIface = "org.bluez.Device1";
constexpr auto kBatteryIface = "org.bluez.Battery1";

using InterfaceProps = QVariantMap;
using ObjectInterfaces = QMap<QString, InterfaceProps>;
using ManagedObjects = QMap<QDBusObjectPath, ObjectInterfaces>;

QVariant unwrap(const QVariant &v)
{
    if (v.userType() == qMetaTypeId<QDBusVariant>())
        return v.value<QDBusVariant>().variant();
    return v;
}

QVariant mapValue(const InterfaceProps &map, const QString &key)
{
    return unwrap(map.value(key));
}
} // namespace

BluetoothModel::BluetoothModel(QObject *parent)
    : QAbstractListModel(parent)
{
    qDBusRegisterMetaType<InterfaceProps>();
    qDBusRegisterMetaType<ObjectInterfaces>();
    qDBusRegisterMetaType<ManagedObjects>();
    ensureService();
    if (m_available) {
        wireSignals();
        refresh();
    }
}

int BluetoothModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_devices.size();
}

QVariant BluetoothModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_devices.size())
        return {};
    const Device &d = m_devices.at(index.row());
    switch (role) {
    case NameRole:
        return d.name;
    case AddressRole:
        return d.address;
    case PathRole:
        return d.path;
    case PairedRole:
        return d.paired;
    case ConnectedRole:
        return d.connected;
    case TrustedRole:
        return d.trusted;
    case BatteryRole:
        return d.battery;
    case StatusLabelRole:
        return statusLabelFor(d);
    default:
        return {};
    }
}

QHash<int, QByteArray> BluetoothModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {AddressRole, "address"},
        {PathRole, "path"},
        {PairedRole, "paired"},
        {ConnectedRole, "connected"},
        {TrustedRole, "trusted"},
        {BatteryRole, "battery"},
        {StatusLabelRole, "statusLabel"},
    };
}

int BluetoothModel::connectedCount() const
{
    int n = 0;
    for (const auto &d : m_devices)
        if (d.connected)
            ++n;
    return n;
}

QString BluetoothModel::statusLabelFor(const Device &d)
{
    if (d.connected) {
        if (d.battery >= 0)
            return QCoreApplication::translate("BluetoothModel", "Connected • Battery %1%")
                .arg(d.battery);
        return QCoreApplication::translate("BluetoothModel", "Connected");
    }
    if (d.paired)
        return QCoreApplication::translate("BluetoothModel", "Paired");
    return QCoreApplication::translate("BluetoothModel", "Available");
}

void BluetoothModel::retranslateUi()
{
    if (rowCount() > 0)
        emit dataChanged(index(0), index(rowCount() - 1));
    emit changed();
}

QVector<BluetoothModel::Device> BluetoothModel::sortDevices(QVector<Device> devices)
{
    std::sort(devices.begin(), devices.end(), [](const Device &a, const Device &b) {
        if (a.connected != b.connected)
            return a.connected && !b.connected;
        if (a.paired != b.paired)
            return a.paired && !b.paired;
        return a.name.localeAwareCompare(b.name) < 0;
    });
    return devices;
}

void BluetoothModel::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

bool BluetoothModel::ensureService()
{
    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        m_available = false;
        m_error = QStringLiteral("System DBus unavailable");
        emit changed();
        return false;
    }
    QDBusInterface om(kBluez, QStringLiteral("/"), kOmIface, bus);
    if (!om.isValid()) {
        m_available = false;
        m_error = QStringLiteral("BlueZ unavailable");
        emit changed();
        return false;
    }
    m_available = true;
    m_error.clear();
    return true;
}

void BluetoothModel::wireSignals()
{
    if (m_signalsWired)
        return;
    auto bus = QDBusConnection::systemBus();
    bus.connect(kBluez, QString(), kOmIface, QStringLiteral("InterfacesAdded"), this, SLOT(onBluezEvent()));
    bus.connect(kBluez, QString(), kOmIface, QStringLiteral("InterfacesRemoved"), this, SLOT(onBluezEvent()));
    bus.connect(kBluez, QString(), kPropsIface, QStringLiteral("PropertiesChanged"), this, SLOT(onBluezEvent()));
    m_signalsWired = true;
}

void BluetoothModel::onBluezEvent()
{
    refresh();
}

void BluetoothModel::refresh()
{
    if (!ensureService())
        return;
    reloadManagedObjects();
    emit changed();
}

void BluetoothModel::reloadManagedObjects()
{
    auto bus = QDBusConnection::systemBus();
    QDBusInterface om(kBluez, QStringLiteral("/"), kOmIface, bus);
    const QDBusReply<ManagedObjects> reply = om.call(QStringLiteral("GetManagedObjects"));
    if (!reply.isValid()) {
        m_error = reply.error().message();
        return;
    }

    m_adapterPath.clear();
    m_adapterName.clear();
    m_powered = false;
    m_discovering = false;
    QVector<Device> devices;

    const ManagedObjects objects = reply.value();
    for (auto it = objects.begin(); it != objects.end(); ++it) {
        const QString path = it.key().path();
        const ObjectInterfaces &ifaces = it.value();

        if (ifaces.contains(QString(kAdapterIface))) {
            const InterfaceProps &ad = ifaces.value(QString(kAdapterIface));
            if (m_adapterPath.isEmpty()) {
                m_adapterPath = path;
                const QVariant alias = mapValue(ad, QStringLiteral("Alias"));
                const QVariant name = mapValue(ad, QStringLiteral("Name"));
                m_adapterName = alias.isValid() ? alias.toString() : name.toString();
                m_powered = mapValue(ad, QStringLiteral("Powered")).toBool();
                m_discovering = mapValue(ad, QStringLiteral("Discovering")).toBool();
            }
        }
        if (ifaces.contains(QString(kDeviceIface))) {
            const InterfaceProps &dev = ifaces.value(QString(kDeviceIface));
            Device d;
            d.path = path;
            const QVariant alias = mapValue(dev, QStringLiteral("Alias"));
            const QVariant name = mapValue(dev, QStringLiteral("Name"));
            d.name = alias.isValid() ? alias.toString() : name.toString();
            d.address = mapValue(dev, QStringLiteral("Address")).toString();
            d.paired = mapValue(dev, QStringLiteral("Paired")).toBool();
            d.connected = mapValue(dev, QStringLiteral("Connected")).toBool();
            d.trusted = mapValue(dev, QStringLiteral("Trusted")).toBool();
            d.battery = -1;
            if (ifaces.contains(QString(kBatteryIface))) {
                const QVariant pct = mapValue(ifaces.value(QString(kBatteryIface)), QStringLiteral("Percentage"));
                if (pct.isValid())
                    d.battery = qBound(0, pct.toInt(), 100);
            }
            if (d.name.isEmpty())
                d.name = d.address;
            devices.append(d);
        }
    }

    devices = sortDevices(devices);
    beginResetModel();
    m_devices = devices;
    endResetModel();
}

void BluetoothModel::setPowered(bool on)
{
    if (!ensureService() || m_adapterPath.isEmpty()) {
        emit operationFailed(QStringLiteral("Bluetooth adapter unavailable"));
        return;
    }
    setBusy(true);
    QDBusInterface props(kBluez, m_adapterPath, kPropsIface, QDBusConnection::systemBus());
    const QDBusReply<void> reply = props.call(QStringLiteral("Set"), QString(kAdapterIface),
                                              QStringLiteral("Powered"),
                                              QVariant::fromValue(QDBusVariant(on)));
    setBusy(false);
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    if (!on)
        stopDiscovery();
    refresh();
}

void BluetoothModel::startDiscovery()
{
    if (!ensureService() || m_adapterPath.isEmpty()) {
        emit operationFailed(QStringLiteral("Bluetooth adapter unavailable"));
        return;
    }
    if (!m_powered) {
        emit operationFailed(QStringLiteral("Turn Bluetooth on first"));
        return;
    }
    QDBusInterface adapter(kBluez, m_adapterPath, kAdapterIface, QDBusConnection::systemBus());
    const QDBusReply<void> reply = adapter.call(QStringLiteral("StartDiscovery"));
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    refresh();
}

void BluetoothModel::stopDiscovery()
{
    if (m_adapterPath.isEmpty())
        return;
    QDBusInterface adapter(kBluez, m_adapterPath, kAdapterIface, QDBusConnection::systemBus());
    adapter.call(QStringLiteral("StopDiscovery"));
    refresh();
}

void BluetoothModel::setPageActive(bool active)
{
    m_pageActive = active;
    if (!active && m_discovering)
        stopDiscovery();
}

void BluetoothModel::connectDevice(const QString &path)
{
    setBusy(true);
    QDBusInterface dev(kBluez, path, kDeviceIface, QDBusConnection::systemBus());
    const QDBusReply<void> reply = dev.call(QStringLiteral("Connect"));
    setBusy(false);
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    refresh();
}

void BluetoothModel::disconnectDevice(const QString &path)
{
    setBusy(true);
    QDBusInterface dev(kBluez, path, kDeviceIface, QDBusConnection::systemBus());
    const QDBusReply<void> reply = dev.call(QStringLiteral("Disconnect"));
    setBusy(false);
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    refresh();
}

void BluetoothModel::pairDevice(const QString &path)
{
    setBusy(true);
    QDBusInterface dev(kBluez, path, kDeviceIface, QDBusConnection::systemBus());
    const QDBusReply<void> reply = dev.call(QStringLiteral("Pair"));
    setBusy(false);
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    refresh();
}

void BluetoothModel::removeDevice(const QString &path)
{
    if (m_adapterPath.isEmpty())
        return;
    setBusy(true);
    QDBusInterface adapter(kBluez, m_adapterPath, kAdapterIface, QDBusConnection::systemBus());
    const QDBusReply<void> reply = adapter.call(QStringLiteral("RemoveDevice"),
                                                QVariant::fromValue(QDBusObjectPath(path)));
    setBusy(false);
    if (!reply.isValid())
        emit operationFailed(reply.error().message());
    refresh();
}
