#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class QTimer;

// Hyprland monitors via hyprctl (argv). Draft → Preview → Keep/Revert with
// single-shot confirmation timer and crash-recovery snapshot. No recurring poll.
class DisplayModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int count READ rowCount NOTIFY changed)
    Q_PROPERTY(bool draftDirty READ draftDirty NOTIFY changed)
    Q_PROPERTY(bool previewActive READ previewActive NOTIFY previewChanged)
    Q_PROPERTY(int previewSecondsLeft READ previewSecondsLeft NOTIFY previewChanged)
    Q_PROPERTY(bool unfinishedPreviewAvailable READ unfinishedPreviewAvailable NOTIFY changed)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY changed)
    Q_PROPERTY(QString selectedName READ selectedName WRITE setSelectedName NOTIFY changed)
    Q_PROPERTY(QVariantMap selectedDraft READ selectedDraft NOTIFY changed)
    Q_PROPERTY(QVariantList selectedModeLabels READ selectedModeLabels NOTIFY changed)
    Q_PROPERTY(int selectedModeIndex READ selectedModeIndex NOTIFY changed)
    Q_PROPERTY(QVariantList layoutPreview READ layoutPreview NOTIFY changed)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        DescriptionRole,
        MakeRole,
        ModelRole,
        WidthRole,
        HeightRole,
        RefreshRateRole,
        ScaleRole,
        XRole,
        YRole,
        EnabledRole,
        FocusedRole,
        ModeLabelRole,
        AvailableModesRole,
    };

    struct Mode {
        int width = 0;
        int height = 0;
        double refreshRate = 0.0;
        QString label; // e.g. "1920×1080 @ 60.05 Hz"
        QString raw;   // hyprland token without Hz suffix ambiguity
    };

    struct Monitor {
        QString name;
        QString description;
        QString make;
        QString model;
        int width = 0;
        int height = 0;
        double refreshRate = 0.0;
        double scale = 1.0;
        int x = 0;
        int y = 0;
        bool enabled = true;
        bool focused = false;
        QVector<Mode> availableModes;
    };

    struct Draft {
        QString name;
        bool enabled = true;
        int width = 0;
        int height = 0;
        double refreshRate = 0.0;
        double scale = 1.0;
        int x = 0;
        int y = 0;
        int modeIndex = 0;
    };

    explicit DisplayModel(QObject *parent = nullptr);
    ~DisplayModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool available() const { return m_available; }
    QString error() const { return m_error; }
    bool draftDirty() const { return m_draftDirty; }
    bool previewActive() const { return m_previewActive; }
    int previewSecondsLeft() const { return m_previewSecondsLeft; }
    bool unfinishedPreviewAvailable() const { return m_unfinishedPreviewAvailable; }
    QString statusMessage() const { return m_statusMessage; }
    QString selectedName() const { return m_selectedName; }
    void setSelectedName(const QString &name);
    QVariantMap selectedDraft() const;
    QVariantList selectedModeLabels() const;
    int selectedModeIndex() const;
    QVariantList layoutPreview() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void resetDraftFromRuntime();
    Q_INVOKABLE void setDraftEnabled(bool enabled);
    Q_INVOKABLE void setDraftModeIndex(int index);
    Q_INVOKABLE void setDraftScale(double scale);
    Q_INVOKABLE void setDraftX(int x);
    Q_INVOKABLE void setDraftY(int y);
    Q_INVOKABLE void applyPositionPreset(const QString &preset, const QString &relativeTo);
    Q_INVOKABLE bool previewChanges();
    Q_INVOKABLE void keepChanges();
    Q_INVOKABLE void revertPreview();
    Q_INVOKABLE bool restoreUnfinishedPreview();
    Q_INVOKABLE void dismissUnfinishedPreview();
    Q_INVOKABLE QVariantList draftMonitorsForSave() const;
    Q_INVOKABLE QStringList otherEnabledMonitorNames() const;

    // Pure helpers / tests.
    static QVector<Monitor> parseMonitorsJson(const QByteArray &json, QString *errorOut = nullptr);
    static bool parseModeToken(const QString &token, Mode *out);
    static bool modeMatches(const Mode &mode, int width, int height, double refresh);
    static int findModeIndex(const QVector<Mode> &modes, int width, int height, double refresh);
    static bool validateScale(double scale, QString *errorOut = nullptr);
    static bool validateLayout(const QVector<Draft> &drafts, QString *errorOut = nullptr);
    static bool canDisableMonitor(const QVector<Draft> &drafts, const QString &name, QString *errorOut = nullptr);
    static QString buildMonitorKeyword(const Draft &d);
    static QByteArray serializeSnapshot(const QVector<Monitor> &monitors);
    static QVector<Monitor> deserializeSnapshot(const QByteArray &json, QString *errorOut = nullptr);
    static double clampScale(double scale);

signals:
    void changed();
    void previewChanged();
    void operationFailed(const QString &message);
    void previewStarted();
    void previewEnded(bool kept);

private:
    QString findHyprctl() const;
    bool runHyprctl(const QStringList &args, QByteArray *stdoutOut = nullptr, QString *errorOut = nullptr);
    void seedDraftsFromRuntime();
    void markDraftDirty();
    Draft *draftForSelected();
    const Draft *draftForSelected() const;
    const Monitor *runtimeByName(const QString &name) const;
    bool applyDraftLayout(const QVector<Draft> &drafts, QString *errorOut);
    bool applyMonitorList(const QVector<Monitor> &monitors, QString *errorOut);
    QString snapshotPath() const;
    bool writeSnapshot(const QVector<Monitor> &monitors);
    bool clearSnapshot();
    void checkUnfinishedSnapshot();
    void startPreviewTimer();
    void stopPreviewTimer(bool kept);
    void tickPreview();
    QVariantMap monitorToMap(const Monitor &m) const;
    QVariantMap draftToMap(const Draft &d) const;

    bool m_available = false;
    QString m_error;
    QString m_statusMessage;
    QString m_hyprctl;
    QVector<Monitor> m_monitors;
    QVector<Draft> m_drafts;
    QVector<Monitor> m_previewBaseline;
    bool m_draftDirty = false;
    bool m_previewActive = false;
    int m_previewSecondsLeft = 0;
    bool m_unfinishedPreviewAvailable = false;
    QString m_selectedName;

    QTimer *m_previewTimer = nullptr;
    QTimer *m_previewTick = nullptr;
};
