#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Async nix flake metadata --json (read-only). Parses only needed fields.
class FlakeMetadataModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString repoPath READ repoPath WRITE setRepoPath NOTIFY repoPathChanged)
    Q_PROPERTY(bool lockPresent READ lockPresent NOTIFY changed)
    Q_PROPERTY(QString lockLastModified READ lockLastModified NOTIFY changed)
    Q_PROPERTY(int lockedInputCount READ lockedInputCount NOTIFY changed)
    Q_PROPERTY(QVariantList inputs READ inputs NOTIFY changed)
    Q_PROPERTY(QString flakeUrl READ flakeUrl NOTIFY changed)
    Q_PROPERTY(QString description READ description NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString details READ details NOTIFY changed)

public:
    explicit FlakeMetadataModel(QObject *parent = nullptr);
    ~FlakeMetadataModel() override;

    QString repoPath() const { return m_repoPath; }
    void setRepoPath(const QString &path);

    bool lockPresent() const { return m_lockPresent; }
    QString lockLastModified() const { return m_lockLastModified; }
    int lockedInputCount() const { return m_lockedInputCount; }
    QVariantList inputs() const { return m_inputs; }
    QString flakeUrl() const { return m_flakeUrl; }
    QString description() const { return m_description; }
    bool busy() const { return m_busy; }
    bool available() const { return m_available; }
    QString error() const { return m_error; }
    QString details() const { return m_details; }

    Q_INVOKABLE void refresh();

    static QVariantMap parseMetadataJson(const QByteArray &json, QString *errorOut = nullptr);
    static QVariantList extractInputs(const QVariantMap &root);
    static void refreshLockFileInfo(const QString &repoPath, bool *present, QString *modifiedLabel);

signals:
    void changed();
    void repoPathChanged();

private:
    void onFinished(int exitCode, QProcess::ExitStatus status);
    void applyParsed(const QVariantMap &parsed);
    void setBusy(bool busy);

    QProcess *m_process = nullptr;
    QString m_repoPath;
    bool m_lockPresent = false;
    QString m_lockLastModified;
    int m_lockedInputCount = 0;
    QVariantList m_inputs;
    QString m_flakeUrl;
    QString m_description;
    bool m_busy = false;
    bool m_available = false;
    QString m_error;
    QString m_details;
};
