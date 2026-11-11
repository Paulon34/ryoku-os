#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QVariantList>
#include <QVector>

class QProcess;
class QTimer;

// PipeWire / WirePlumber sound control via wpctl (argv). Manual + post-action refresh.
// Optional one-shot debounce timer for slider volume (not a recurring poll).
class SoundModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int outputVolume READ outputVolume NOTIFY changed)
    Q_PROPERTY(bool outputMuted READ outputMuted NOTIFY changed)
    Q_PROPERTY(QString defaultOutputName READ defaultOutputName NOTIFY changed)
    Q_PROPERTY(int inputVolume READ inputVolume NOTIFY changed)
    Q_PROPERTY(bool inputMuted READ inputMuted NOTIFY changed)
    Q_PROPERTY(QString defaultInputName READ defaultInputName NOTIFY changed)
    Q_PROPERTY(QVariantList sinkDevices READ sinkDevices NOTIFY changed)
    Q_PROPERTY(QVariantList sourceDevices READ sourceDevices NOTIFY changed)
    Q_PROPERTY(int count READ rowCount NOTIFY changed)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        IsDefaultRole,
        IsSinkRole,
    };

    struct Node {
        quint32 id = 0;
        QString name;
        bool isDefault = false;
        bool isSink = true;
    };

    explicit SoundModel(QObject *parent = nullptr);
    ~SoundModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool available() const { return m_available; }
    QString error() const { return m_error; }
    int outputVolume() const { return m_outputVolume; }
    bool outputMuted() const { return m_outputMuted; }
    QString defaultOutputName() const { return m_defaultOutputName; }
    int inputVolume() const { return m_inputVolume; }
    bool inputMuted() const { return m_inputMuted; }
    QString defaultInputName() const { return m_defaultInputName; }
    QVariantList sinkDevices() const { return m_sinkDevices; }
    QVariantList sourceDevices() const { return m_sourceDevices; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setOutputVolume(int percent);
    Q_INVOKABLE void setOutputMuted(bool muted);
    Q_INVOKABLE void setInputVolume(int percent);
    Q_INVOKABLE void setInputMuted(bool muted);
    Q_INVOKABLE void setDefaultSink(quint32 id);
    Q_INVOKABLE void setDefaultSource(quint32 id);
    // Debounced slider path — coalesces rapid moves into one wpctl call.
    Q_INVOKABLE void scheduleOutputVolume(int percent);
    Q_INVOKABLE void scheduleInputVolume(int percent);

    static int clampVolume(int percent);
    static bool parseVolumeLine(const QByteArray &line, int *volumeOut, bool *mutedOut);
    static QVector<Node> parseWpctlStatus(const QByteArray &text, bool sinks);

signals:
    void changed();
    void operationFailed(const QString &message);

private:
    QString findWpctl() const;
    bool runWpctl(const QStringList &args, QByteArray *stdoutOut = nullptr, QString *errorOut = nullptr);
    void applyPendingVolumes();

    bool m_available = false;
    QString m_error;
    int m_outputVolume = 0;
    bool m_outputMuted = false;
    QString m_defaultOutputName;
    int m_inputVolume = 0;
    bool m_inputMuted = false;
    QString m_defaultInputName;
    QVector<Node> m_nodes;
    QVariantList m_sinkDevices;
    QVariantList m_sourceDevices;
    QString m_wpctl;

    QTimer *m_volumeDebounce = nullptr;
    int m_pendingOutput = -1;
    int m_pendingInput = -1;
};
