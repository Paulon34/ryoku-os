#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Read-only NixOS generations via nixos-rebuild list-generations --json.
class GenerationsModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList generations READ generations NOTIFY changed)
    Q_PROPERTY(int currentGeneration READ currentGeneration NOTIFY changed)
    Q_PROPERTY(int profileGeneration READ profileGeneration NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString details READ details NOTIFY changed)
    Q_PROPERTY(int displayLimit READ displayLimit CONSTANT)

public:
    explicit GenerationsModel(QObject *parent = nullptr);
    ~GenerationsModel() override;

    QVariantList generations() const { return m_generations; }
    int currentGeneration() const { return m_currentGeneration; }
    int profileGeneration() const { return m_profileGeneration; }
    bool busy() const { return m_busy; }
    bool available() const { return m_available; }
    QString error() const { return m_error; }
    QString details() const { return m_details; }
    int displayLimit() const { return 10; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap generationAt(int generation) const;
    Q_INVOKABLE void retranslateUi();

    // Keep at most `limit` newest generations (by generation number).
    static QVariantList parseListGenerationsJson(const QByteArray &json, int limit,
                                                 int *currentOut = nullptr,
                                                 QString *errorOut = nullptr);
    static int parseProfileGenerationFromSymlinkTarget(const QString &targetOrName);

signals:
    void changed();

private:
    void onFinished(int exitCode, QProcess::ExitStatus status);
    void setBusy(bool busy);

    QProcess *m_process = nullptr;
    QVariantList m_generations;
    int m_currentGeneration = -1;
    int m_profileGeneration = -1;
    bool m_busy = false;
    bool m_available = false;
    QString m_error;
    QString m_details;
};
