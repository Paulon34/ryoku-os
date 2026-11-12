#pragma once

#include <QByteArray>
#include <QMetaObject>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class ApplyController;
class QTimer;

// 7H-B: unprivileged flake lock check / update / revert / validate bridge.
// Never runs nixos-rebuild. Does not mutate ryokuSettingsHash semantics.
class FlakeUpdateModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString repoPath READ repoPath WRITE setRepoPath NOTIFY repoPathChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString phase READ phase NOTIFY changed)
    Q_PROPERTY(QString statusLabel READ statusLabel NOTIFY changed)
    Q_PROPERTY(QVariantList inputs READ inputs NOTIFY changed)
    Q_PROPERTY(bool checkRan READ checkRan NOTIFY changed)
    Q_PROPERTY(bool updatesAvailable READ updatesAvailable NOTIFY changed)
    Q_PROPERTY(bool pendingLockChange READ pendingLockChange NOTIFY changed)
    Q_PROPERTY(bool canRevert READ canRevert NOTIFY changed)
    Q_PROPERTY(QVariantList lockDiff READ lockDiff NOTIFY changed)
    Q_PROPERTY(QString details READ details NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString validationLabel READ validationLabel NOTIFY changed)
    Q_PROPERTY(bool canValidatePending READ canValidatePending NOTIFY changed)
    Q_PROPERTY(bool repoWasDirtyBeforeUpdate READ repoWasDirtyBeforeUpdate WRITE setRepoWasDirtyBeforeUpdate NOTIFY changed)
    Q_PROPERTY(QString lockfileRebuildHint READ lockfileRebuildHint NOTIFY changed)
    Q_PROPERTY(QString runningNixpkgsHint READ runningNixpkgsHint NOTIFY changed)

public:
    explicit FlakeUpdateModel(QObject *parent = nullptr);
    ~FlakeUpdateModel() override;

    QString repoPath() const { return m_repoPath; }
    void setRepoPath(const QString &path);
    void setApplyController(ApplyController *ctrl);

    bool busy() const { return m_busy; }
    QString phase() const { return m_phase; }
    QString statusLabel() const;
    QVariantList inputs() const { return m_inputs; }
    bool checkRan() const { return m_checkRan; }
    bool updatesAvailable() const { return m_updatesAvailable; }
    bool pendingLockChange() const { return m_pendingLockChange; }
    bool canRevert() const { return m_canRevert; }
    QVariantList lockDiff() const { return m_lockDiff; }
    QString details() const { return m_details; }
    QString error() const { return m_error; }
    QString validationLabel() const;
    bool canValidatePending() const;
    bool repoWasDirtyBeforeUpdate() const { return m_repoWasDirtyBeforeUpdate; }
    void setRepoWasDirtyBeforeUpdate(bool dirty);
    QString lockfileRebuildHint() const { return m_lockfileRebuildHint; }
    QString runningNixpkgsHint() const { return m_runningNixpkgsHint; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void updateAll();
    Q_INVOKABLE void updateInput(const QString &inputName);
    Q_INVOKABLE void revertUpdate();
    Q_INVOKABLE void validatePending();
    Q_INVOKABLE void retranslateUi();

    // --- testable pure helpers ---
    static QVariantList parseLockRootInputs(const QByteArray &lockJson, QString *errorOut = nullptr);
    static QString flakeUrlFromOriginal(const QVariantMap &original);
    static QString shortRev(const QString &rev);
    static QString compareUpdateStatus(const QString &lockedRev, const QString &remoteRev);
    static QVariantList diffLockedRevisions(const QByteArray &oldLock, const QByteArray &newLock);
    static bool writeAtomicFile(const QString &path, const QByteArray &bytes, QString *errorOut = nullptr);
    static bool isValidInputName(const QString &name);
    static bool isAllowlistedFlakeUpdateArgs(const QStringList &args, const QStringList &knownInputs);
    static QString parseMetadataRevision(const QByteArray &json, QString *errorOut = nullptr);
    static QString classifyProcessFailure(int exitCode, QProcess::ExitStatus status,
                                          QProcess::ProcessError processError,
                                          const QByteArray &stderrBytes);
    static QString lockContentSha256(const QByteArray &bytes);
    static QString rebuildHintFor(bool pendingLockChange, bool settingsApplied);
    static QString nixpkgsRunningHint(const QString &lockedNixpkgsRev,
                                      const QString &runningNixpkgsRev);

signals:
    void changed();
    void repoPathChanged();
    void lockfileChanged();

private:
    enum class Op { None, Check, UpdateAll, UpdateOne, Validate };

    void setBusy(bool busy);
    void setPhase(const QString &phase);
    void appendDetails(const QString &chunk);
    void loadInputsFromLock();
    bool snapshotLockBeforeMutation(QString *errorOut);
    void finishUpdateFromProcess(int exitCode, QProcess::ExitStatus status);
    void startNextCheck();
    void onCheckProcessFinished(int exitCode, QProcess::ExitStatus status);
    void onUpdateProcessFinished(int exitCode, QProcess::ExitStatus status);
    void onCheckTimeout();
    void onUpdateTimeout();
    void onApplyControllerChanged();
    void killActiveProcess();
    void syncApplyBridge();
    void refreshRunningNixpkgsHint();
    QStringList knownInputNames() const;
    QString lockPath() const;

    ApplyController *m_apply = nullptr;
    QMetaObject::Connection m_applyConn;
    QProcess *m_process = nullptr;
    QTimer *m_timeout = nullptr;
    QString m_repoPath;
    QString m_nix = QStringLiteral("nix");

    bool m_busy = false;
    QString m_phase = QStringLiteral("idle");
    QVariantList m_inputs;
    bool m_checkRan = false;
    bool m_updatesAvailable = false;
    bool m_pendingLockChange = false;
    bool m_canRevert = false;
    bool m_repoWasDirtyBeforeUpdate = false;
    QVariantList m_lockDiff;
    QString m_details;
    QString m_error;
    QString m_validationLabel = QStringLiteral("Not run");
    QString m_lockfileRebuildHint;
    QString m_runningNixpkgsHint;

    QByteArray m_lockSnapshot;
    QString m_lockSnapshotHash;
    QString m_updateTargetInput; // empty = all
    Op m_op = Op::None;

    int m_checkIndex = 0;
    QStringList m_checkQueue;
};
