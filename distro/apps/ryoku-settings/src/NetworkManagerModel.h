#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

class QDBusConnection;
class QDBusInterface;

// NetworkManager DBus backend (Wi-Fi + Ethernet overview). No settings.json state.
class NetworkManagerModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)
    Q_PROPERTY(bool wifiHardwareAvailable READ wifiHardwareAvailable NOTIFY changed)
    Q_PROPERTY(QString connectivityLabel READ connectivityLabel NOTIFY changed)
    Q_PROPERTY(QString connectedSsid READ connectedSsid NOTIFY changed)
    Q_PROPERTY(int connectedStrength READ connectedStrength NOTIFY changed)
    Q_PROPERTY(QString primaryDevice READ primaryDevice NOTIFY changed)
    Q_PROPERTY(QString ethernetLabel READ ethernetLabel NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY changed)

public:
    enum Roles {
        SsidRole = Qt::UserRole + 1,
        StrengthRole,
        SecuredRole,
        SecurityLabelRole,
        ConnectedRole,
        BssidRole,
        PathRole,
    };

    struct AccessPoint {
        QString path;
        QString ssid;
        QString bssid;
        int strength = 0;
        bool secured = false;
        bool connected = false;
    };

    explicit NetworkManagerModel(QObject *parent = nullptr);
    ~NetworkManagerModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool available() const { return m_available; }
    QString error() const { return m_error; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    bool wifiHardwareAvailable() const { return m_wifiHw; }
    QString connectivityLabel() const { return m_connectivityLabel; }
    QString connectedSsid() const { return m_connectedSsid; }
    int connectedStrength() const { return m_connectedStrength; }
    QString primaryDevice() const { return m_primaryDevice; }
    QString ethernetLabel() const { return m_ethernetLabel; }
    bool busy() const { return m_busy; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void requestScan();
    Q_INVOKABLE void setWifiEnabled(bool enabled);
    Q_INVOKABLE void disconnectWifi();
    // password empty for open / known profiles. Never logged.
    Q_INVOKABLE void connectToNetwork(const QString &ssid, const QString &password = QString());
    Q_INVOKABLE void retranslateUi();

public slots:
    void onNmEvent();

    // Pure helpers / tests.
    static QString securityLabel(bool secured);
    static QVector<AccessPoint> sortAccessPoints(QVector<AccessPoint> aps);
    static bool isSecuredFromFlags(quint32 flags, quint32 wpa, quint32 rsn);
    static int clampStrength(int strength);

signals:
    void changed();
    void busyChanged();
    void operationFailed(const QString &message);
    void passwordRequired(const QString &ssid);

private:
    void setBusy(bool busy);
    void setError(const QString &err);
    bool ensureService();
    void wireSignals();
    void reloadDevices();
    void reloadAccessPoints();
    void reloadActiveConnection();
    QString findWifiDevicePath() const;
    QString findKnownConnectionPath(const QString &ssid) const;
    QByteArray ssidBytes(const QString &ssid) const;

    bool m_available = false;
    bool m_wifiEnabled = false;
    bool m_wifiHw = false;
    bool m_busy = false;
    QString m_error;
    QString m_connectivityLabel = QStringLiteral("Unavailable");
    QString m_connectedSsid;
    int m_connectedStrength = 0;
    QString m_primaryDevice;
    QString m_ethernetLabel = QStringLiteral("Not present");
    QString m_wifiDevicePath;
    QString m_activeApPath;
    QVector<AccessPoint> m_aps;
    bool m_signalsWired = false;
};
