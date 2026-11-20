#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QVector>

// BlueZ DBus backend via ObjectManager. No settings.json device state.
class BluetoothModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool powered READ powered NOTIFY changed)
    Q_PROPERTY(bool discovering READ discovering NOTIFY changed)
    Q_PROPERTY(int connectedCount READ connectedCount NOTIFY changed)
    Q_PROPERTY(QString adapterName READ adapterName NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY changed)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        AddressRole,
        PathRole,
        PairedRole,
        ConnectedRole,
        TrustedRole,
        BatteryRole, // -1 if unknown
        StatusLabelRole,
    };

    struct Device {
        QString path;
        QString name;
        QString address;
        bool paired = false;
        bool connected = false;
        bool trusted = false;
        int battery = -1;
    };

    explicit BluetoothModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool available() const { return m_available; }
    QString error() const { return m_error; }
    bool powered() const { return m_powered; }
    bool discovering() const { return m_discovering; }
    int connectedCount() const;
    QString adapterName() const { return m_adapterName; }
    bool busy() const { return m_busy; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setPowered(bool on);
    Q_INVOKABLE void startDiscovery();
    Q_INVOKABLE void stopDiscovery();
    Q_INVOKABLE void connectDevice(const QString &path);
    Q_INVOKABLE void disconnectDevice(const QString &path);
    Q_INVOKABLE void pairDevice(const QString &path);
    Q_INVOKABLE void removeDevice(const QString &path);
    Q_INVOKABLE void setPageActive(bool active);
    Q_INVOKABLE void retranslateUi();

public slots:
    void onBluezEvent();

    static QVector<Device> sortDevices(QVector<Device> devices);
    static QString statusLabelFor(const Device &d);

signals:
    void changed();
    void busyChanged();
    void operationFailed(const QString &message);

private:
    bool ensureService();
    void wireSignals();
    void setBusy(bool busy);
    void reloadManagedObjects();

    bool m_available = false;
    bool m_powered = false;
    bool m_discovering = false;
    bool m_busy = false;
    bool m_pageActive = false;
    bool m_signalsWired = false;
    QString m_error;
    QString m_adapterPath;
    QString m_adapterName;
    QVector<Device> m_devices;
};
