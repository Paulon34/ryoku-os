#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QDBusInterface;
class QTimer;

// Battery (UPower DBus), brightness (brightnessctl argv), power profiles (ppd DBus).
// No recurring poll — DBus signals + manual refresh + brightness debounce.
class PowerModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool batteryAvailable READ batteryAvailable NOTIFY changed)
    Q_PROPERTY(bool batteryPresent READ batteryPresent NOTIFY changed)
    Q_PROPERTY(double batteryPercentage READ batteryPercentage NOTIFY changed)
    Q_PROPERTY(QString batteryState READ batteryState NOTIFY changed)
    Q_PROPERTY(QString batteryStateLabel READ batteryStateLabel NOTIFY changed)
    Q_PROPERTY(QString batteryTimeLabel READ batteryTimeLabel NOTIFY changed)
    Q_PROPERTY(double energyRate READ energyRate NOTIFY changed)
    Q_PROPERTY(bool energyRateValid READ energyRateValid NOTIFY changed)
    Q_PROPERTY(QString batteryError READ batteryError NOTIFY changed)

    Q_PROPERTY(bool brightnessAvailable READ brightnessAvailable NOTIFY changed)
    Q_PROPERTY(int brightness READ brightness NOTIFY changed)
    Q_PROPERTY(QString brightnessError READ brightnessError NOTIFY changed)

    Q_PROPERTY(bool profilesAvailable READ profilesAvailable NOTIFY changed)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY changed)
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY changed)
    Q_PROPERTY(QString profilesError READ profilesError NOTIFY changed)

    Q_PROPERTY(QString lidBehaviorLabel READ lidBehaviorLabel NOTIFY changed)
    Q_PROPERTY(QString suspendLabel READ suspendLabel NOTIFY changed)
    Q_PROPERTY(QString idleLabel READ idleLabel NOTIFY changed)

public:
    explicit PowerModel(QObject *parent = nullptr);
    ~PowerModel() override;

    bool batteryAvailable() const { return m_batteryAvailable; }
    bool batteryPresent() const { return m_batteryPresent; }
    double batteryPercentage() const { return m_batteryPercentage; }
    QString batteryState() const { return m_batteryState; }
    QString batteryStateLabel() const { return m_batteryStateLabel; }
    QString batteryTimeLabel() const { return m_batteryTimeLabel; }
    double energyRate() const { return m_energyRate; }
    bool energyRateValid() const { return m_energyRateValid; }
    QString batteryError() const { return m_batteryError; }

    bool brightnessAvailable() const { return m_brightnessAvailable; }
    int brightness() const { return m_brightness; }
    QString brightnessError() const { return m_brightnessError; }

    bool profilesAvailable() const { return m_profilesAvailable; }
    QString activeProfile() const { return m_activeProfile; }
    QVariantList profiles() const { return m_profiles; }
    QString profilesError() const { return m_profilesError; }

    QString lidBehaviorLabel() const { return m_lidBehaviorLabel; }
    QString suspendLabel() const { return m_suspendLabel; }
    QString idleLabel() const { return m_idleLabel; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setBrightness(int percent);
    Q_INVOKABLE void scheduleBrightness(int percent);
    Q_INVOKABLE void setPowerProfile(const QString &profile);

    static int clampBrightness(int percent);
    // brightnessctl 0.5 argv for set — `-n` is a flag (no value).
    static QStringList brightnessSetArgs(int percent, bool withBacklightClass = true);
    static QString mapBatteryState(quint32 state);
    static QString formatBatteryTime(qint64 seconds);
    static QString mapProfileId(const QString &id);
    static QString profileDisplayName(const QString &id);

signals:
    void changed();
    void operationFailed(const QString &message);

private slots:
    void onUPowerChanged();
    void onProfilesChanged();

private:
    void refreshBattery();
    void refreshBrightness();
    void refreshProfiles();
    void refreshSleepAndLid();
    void wireUPowerSignals();
    void wireProfileSignals();
    QString findBrightnessctl() const;
    bool runBrightnessctl(const QStringList &args, QByteArray *stdoutOut = nullptr, QString *errorOut = nullptr);
    void applyPendingBrightness();

    bool m_batteryAvailable = false;
    bool m_batteryPresent = false;
    double m_batteryPercentage = 0.0;
    QString m_batteryState;
    QString m_batteryStateLabel;
    QString m_batteryTimeLabel;
    double m_energyRate = 0.0;
    bool m_energyRateValid = false;
    QString m_batteryError;

    bool m_brightnessAvailable = false;
    int m_brightness = 0;
    QString m_brightnessError;
    QString m_brightnessctl;

    bool m_profilesAvailable = false;
    QString m_activeProfile;
    QVariantList m_profiles;
    QString m_profilesError;

    QString m_lidBehaviorLabel = QStringLiteral("Unknown");
    QString m_suspendLabel = QStringLiteral("Unknown");
    QString m_idleLabel = QStringLiteral("Unknown");

    QTimer *m_brightnessDebounce = nullptr;
    int m_pendingBrightness = -1;
};
