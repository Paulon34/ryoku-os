#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class QFileSystemWatcher;
class SettingsStore;

// Apply Engine (7G-A hash state + 7G-B privileged apply/rollback).
//
// Unprivileged GUI compares current hash vs /etc/ryoku/applied-settings-hash.
// System apply/rollback runs via pkexec → ryoku-settings-apply (allowlisted).
// No sudo. No shell. No password handling in QML.
class ApplyController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    Q_PROPERTY(QString progressStage READ progressStage NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)
    Q_PROPERTY(bool needsUserApply READ needsUserApply NOTIFY changed)
    Q_PROPERTY(bool needsSystemApply READ needsSystemApply NOTIFY changed)
    Q_PROPERTY(bool canValidate READ canValidate NOTIFY changed)
    Q_PROPERTY(bool canApply READ canApply NOTIFY changed)
    Q_PROPERTY(bool canRollback READ canRollback NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool helperInstalled READ helperInstalled NOTIFY changed)
    Q_PROPERTY(QString bootstrapHint READ bootstrapHint NOTIFY changed)
    Q_PROPERTY(QString currentHash READ currentHash NOTIFY changed)
    Q_PROPERTY(QString appliedHash READ appliedHash NOTIFY changed)
    Q_PROPERTY(bool appliedMarkerPresent READ appliedMarkerPresent NOTIFY changed)
    Q_PROPERTY(QVariantList userPlan READ userPlan NOTIFY changed)
    Q_PROPERTY(QVariantList systemPlan READ systemPlan NOTIFY changed)
    Q_PROPERTY(QString applyLog READ applyLog NOTIFY logChanged)
    Q_PROPERTY(QString lastValidationSummary READ lastValidationSummary NOTIFY changed)
    Q_PROPERTY(QString previousGeneration READ previousGeneration NOTIFY changed)
    Q_PROPERTY(bool rollbackAvailable READ rollbackAvailable NOTIFY changed)
    Q_PROPERTY(bool unsavedDraft READ unsavedDraft WRITE setUnsavedDraft NOTIFY changed)
    Q_PROPERTY(bool lockfilePendingRebuild READ lockfilePendingRebuild NOTIFY changed)

public:
    static constexpr const char *StatusApplied = "Applied";
    static constexpr const char *StatusNeedsApply = "NeedsApply";
    static constexpr const char *StatusValidating = "Validating";
    static constexpr const char *StatusReady = "Ready";
    static constexpr const char *StatusValidationFailed = "ValidationFailed";
    static constexpr const char *StatusAwaitingAuthorization = "AwaitingAuthorization";
    static constexpr const char *StatusApplying = "Applying";
    static constexpr const char *StatusApplyFailed = "ApplyFailed";
    static constexpr const char *StatusAuthorizationDenied = "AuthorizationDenied";
    static constexpr const char *StatusAuthorizationError = "AuthorizationError";
    static constexpr const char *StatusRollingBack = "RollingBack";
    static constexpr const char *StatusRollbackFailed = "RollbackFailed";
    static constexpr const char *StatusSwitchingGeneration = "SwitchingGeneration";
    static constexpr const char *StatusSwitchFailed = "SwitchFailed";
    static constexpr const char *StatusIdle = "Idle";
    static constexpr const char *StatusHashError = "HashError";

    // Prefer NixOS setuid wrapper; fall back to Debian /usr/bin/pkexec.
    static constexpr const char *SystemPkexecPath = "/run/wrappers/bin/pkexec";
    static constexpr const char *DebianPkexecPath = "/usr/bin/pkexec";

    struct PkexecClassification {
        QString status;
        QString message;
        int exitCode = -1;
    };

    struct NixEvalHashResult {
        bool ok = false;
        QString hash;
        QString error;
        QString stderrWarning; // non-fatal (e.g. dirty Git tree); never fails alone
    };

    enum class Scope { User, System };
    enum class PrivilegedOp { Apply, Rollback, SwitchGeneration };

    struct PlanItem {
        QString id;
        QString label;
        Scope scope = Scope::System;
    };

    explicit ApplyController(QObject *parent = nullptr);
    ~ApplyController() override;

    void setRepoPath(const QString &repoPath);
    void setSettingsStore(SettingsStore *store);

    QString status() const { return m_status; }
    QString statusText() const;
    // Re-emit NOTIFY after QTranslator swap (i18n). Does not change apply state.
    Q_INVOKABLE void retranslateUi();
    QString progressStage() const { return m_progressStage; }
    QString lastError() const { return m_lastError; }
    bool needsUserApply() const { return m_needsUserApply; }
    bool needsSystemApply() const { return m_needsSystemApply; }
    bool canValidate() const;
    bool canApply() const;
    bool canRollback() const;
    Q_INVOKABLE bool canSwitchGeneration(int generation) const;
    bool busy() const { return m_busy; }
    bool helperInstalled() const { return m_helperInstalled; }
    QString bootstrapHint() const;
    QString currentHash() const { return m_currentHash; }
    QString appliedHash() const { return m_appliedHash; }
    bool appliedMarkerPresent() const { return m_appliedMarkerPresent; }
    QVariantList userPlan() const { return m_userPlan; }
    QVariantList systemPlan() const { return m_systemPlan; }
    QString applyLog() const { return m_applyLog; }
    QString lastValidationSummary() const { return m_lastValidationSummary; }
    QString previousGeneration() const { return m_previousGeneration; }
    bool rollbackAvailable() const { return m_rollbackAvailable; }
    bool unsavedDraft() const { return m_unsavedDraft; }
    void setUnsavedDraft(bool unsaved);
    bool lockfilePendingRebuild() const { return m_lockfilePendingRebuild; }
    void setLockfilePendingRebuild(bool pending);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void validate();
    Q_INVOKABLE void apply();
    Q_INVOKABLE void rollback();
    Q_INVOKABLE void switchGeneration(int generation);
    Q_INVOKABLE void clearLog();
    Q_INVOKABLE QVariantMap generationSwitchPreview(int generation) const;

    // Pure helpers / tests.
    static QString appliedMarkerPath();
    static QString helperPathFile();
    static QString normalizeHash(const QString &raw);
    static bool isValidSha256Hex(const QString &hash);
    static bool hashesMatch(const QString &current, const QString &applied);
    static QString statusFromHashes(bool markerPresent,
                                    bool currentResolved,
                                    bool currentFailed,
                                    const QString &current,
                                    const QString &applied);
    static QString needsApplyReason(bool markerPresent,
                                    bool currentResolved,
                                    bool currentFailed,
                                    const QString &current,
                                    const QString &applied);
    static QVector<PlanItem> knownInventory();
    static QVariantList planToVariant(const QVector<PlanItem> &items, Scope scope);
    static QVector<PlanItem> buildPlanForNeedsApply(bool needsApply);
    static QString parseValidationResult(int exitCode, const QByteArray &combinedOutput);
    static bool isAllowlistedNixEvalArgs(const QStringList &args);
    static bool isAllowlistedFlakeCheckArgs(const QStringList &args);
    static QString hashFromNixEvalStdout(const QByteArray &stdoutBytes);
    // Contract: success = NormalExit + exit 0 + valid SHA-256 stdout.
    // stderr (e.g. dirty Git warning) never invalidates a successful eval by itself.
    static NixEvalHashResult interpretNixEvalHashResult(int exitCode,
                                                        int exitStatus,
                                                        const QByteArray &stdoutBytes,
                                                        const QByteArray &stderrBytes);
    static bool isAllowlistedHelperOperation(const QString &op);
    static QStringList buildPkexecArgv(const QString &pkexec,
                                       const QString &helperAbsPath,
                                       const QString &operation);
    static QStringList buildPkexecArgv(const QString &pkexec,
                                       const QString &helperAbsPath,
                                       const QString &operation,
                                       int generation);
    static QString systemPkexecPath();
    static bool isAllowedPkexecPath(const QString &path);
    static QString missingSystemPkexecMessage();
    // Resolve symlinks → absolute store path (must match polkit exec.path).
    static QString canonicalizeHelperPath(const QString &path);
    static bool helperPathMatchesPolicyAnnotation(const QString &invokedPath,
                                                  const QString &policyExecPath);

    // Generation switch helpers (testable; no privileged side effects).
    static bool parseStrictGenerationNumber(const QString &text, int *out);
    static QString systemGenerationLinkPath(int generation);
    static bool validateSystemGenerationExists(int generation, QString *canonicalOut,
                                               QString *errorOut);
    static int readProfileGenerationNumber();
    static QString readProfileCanonicalPath();
    static QString readCurrentSystemCanonicalPath();
    static bool activeGenerationMatches(int generation);
    // Success ONLY when targetActive (current == profile == requested store path).
    // exit0 + mismatch → SwitchFailed. Pre-exec pkexec/auth failures keep their status
    // (never mislabeled as SwitchFailed / "target mismatch").
    static QString reconcileSwitchGenerationVerification(bool targetActive,
                                                         bool processLookedOk,
                                                         bool wasAuthorizationDenied,
                                                         bool wasFailedToStart,
                                                         const QString &classifiedStatus,
                                                         const QString &processDiagnostic,
                                                         QString *warningOut);
    // Classify pkexec from exitStatus / ProcessError first — exitCode only if NormalExit.
    static PkexecClassification classifyPkexecResult(int exitCode,
                                                     int exitStatus,
                                                     int processError,
                                                     const QString &errorString,
                                                     const QByteArray &stdoutBytes,
                                                     const QByteArray &stderrBytes,
                                                     bool wasRollback);
    // Backward-compatible overload used by pure unit tests (NormalExit assumed unless exitStatus set).
    static PkexecClassification classifyPkexecResult(int exitCode,
                                                     int exitStatus,
                                                     const QByteArray &stdoutBytes,
                                                     const QByteArray &stderrBytes,
                                                     bool wasRollback);
    static QString mapPrivilegedResult(int exitCode,
                                       bool hashMatchAfter,
                                       bool wasRollback,
                                       QString *statusOut);
    // Single source of truth for page badges (Apps Flatpak etc.): draft vs apply state.
    static QString declarativePageStatusLabel(bool hasError,
                                              bool unsavedDraft,
                                              bool needsSystemApply,
                                              const QString &applyStatus);
    // After privileged process ends: marker/hash is authoritative.
    // processLookedOk = NormalExit+0 and not FailedToStart.
    // Returns final status; fills warningOut when Applied despite abnormal process.
    static QString reconcilePrivilegedVerification(bool hashMatch,
                                                   bool processLookedOk,
                                                   bool wasRollback,
                                                   bool wasAuthorizationDenied,
                                                   bool wasFailedToStart,
                                                   const QString &processDiagnostic,
                                                   QString *warningOut);

signals:
    void changed();
    void logChanged();
    void operationFailed(const QString &message);

private:
    void watchMarker();
    void readAppliedMarker();
    void detectHelper();
    void captureCurrentSystem();
    void requestCurrentHash();
    void onCurrentHashFinished(int exitCode, QProcess::ExitStatus status);
    void onValidateFinished(int exitCode, QProcess::ExitStatus status);
    void onPrivilegedFinished(int exitCode, QProcess::ExitStatus status);
    void onPrivilegedErrorOccurred(QProcess::ProcessError error);
    void launchPrivileged(PrivilegedOp op);
    void launchPrivilegedSwitch(int generation);
    void finishApplyVerification();
    void finishSwitchGenerationVerification();
    void appendLog(const QString &chunk);
    void recomputeApplyState();
    void rebuildPlan();
    void setStatus(const QString &status);
    void setBusy(bool busy);
    QString findNix() const;
    QString findPkexec() const;
    bool repoLooksValid() const;
    bool privilegedInFlight() const;

    QString m_repoPath;
    SettingsStore *m_store = nullptr;
    QFileSystemWatcher *m_watcher = nullptr;
    QProcess *m_hashProcess = nullptr;
    QProcess *m_validateProcess = nullptr;
    QProcess *m_privilegedProcess = nullptr;
    int m_hashGeneration = 0;
    int m_privilegedGeneration = 0;

    QString m_status = QString::fromLatin1(StatusIdle);
    QString m_progressStage;
    QString m_lastError;
    QString m_currentHash;
    QString m_appliedHash;
    bool m_appliedMarkerPresent = false;
    bool m_currentHashResolved = false;
    bool m_currentHashFailed = false;
    bool m_needsUserApply = false;
    bool m_needsSystemApply = false;
    bool m_busy = false;
    bool m_unsavedDraft = false;
    bool m_lockfilePendingRebuild = false;
    bool m_validatedOk = false;
    bool m_applyAfterValidate = false;
    bool m_helperInstalled = false;
    bool m_rollbackAvailable = false;
    bool m_awaitingHashAfterPrivileged = false;
    PrivilegedOp m_pendingPrivileged = PrivilegedOp::Apply;
    int m_switchTargetGeneration = -1;
    int m_privilegedLastProcessError = -1; // QProcess::ProcessError or -1
    QString m_privilegedErrorString;
    QString m_privilegedProcessDiagnostic;
    QString m_privilegedClassifiedStatus;
    bool m_privilegedProcessLookedOk = false;
    bool m_privilegedWasAuthDenied = false;
    bool m_privilegedWasFailedToStart = false;
    QString m_helperPath;
    QString m_pkexec;
    QVariantList m_userPlan;
    QVariantList m_systemPlan;
    QString m_applyLog;
    QString m_lastValidationSummary;
    QString m_previousGeneration;
    QString m_nix;
};
