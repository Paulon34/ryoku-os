#pragma once

#include <QByteArray>
#include <QObject>
#include <QProcess>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// 7H-D: safe Git workflow MVP (status / diff / stage / unstage / commit / fetch / push).
// No destructive ops (reset --hard, discard, force push, pull/merge/rebase, …).
class GitStatusModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString statusLabel READ statusLabel NOTIFY changed)
    Q_PROPERTY(bool clean READ clean NOTIFY changed)
    Q_PROPERTY(QString branch READ branch NOTIFY changed)
    Q_PROPERTY(QString lastCommitHash READ lastCommitHash NOTIFY changed)
    Q_PROPERTY(QString lastCommitSubject READ lastCommitSubject NOTIFY changed)
    Q_PROPERTY(QString headSummaryText READ headSummaryText NOTIFY changed)
    Q_PROPERTY(QStringList changedFiles READ changedFiles NOTIFY changed)
    Q_PROPERTY(int changedFileCount READ changedFileCount NOTIFY changed)
    Q_PROPERTY(QString workingTreeLabel READ workingTreeLabel NOTIFY changed)
    Q_PROPERTY(QString pushStatusLabel READ pushStatusLabel NOTIFY changed)
    Q_PROPERTY(QString upstream READ upstream NOTIFY changed)
    Q_PROPERTY(int aheadCount READ aheadCount NOTIFY changed)
    Q_PROPERTY(int behindCount READ behindCount NOTIFY changed)
    Q_PROPERTY(bool detachedHead READ detachedHead NOTIFY changed)
    Q_PROPERTY(bool hasConflicts READ hasConflicts NOTIFY changed)
    Q_PROPERTY(bool hasUpstream READ hasUpstream NOTIFY changed)
    Q_PROPERTY(QVariantList stagedEntries READ stagedEntries NOTIFY changed)
    Q_PROPERTY(QVariantList unstagedEntries READ unstagedEntries NOTIFY changed)
    Q_PROPERTY(QVariantList untrackedEntries READ untrackedEntries NOTIFY changed)
    Q_PROPERTY(QVariantList conflictEntries READ conflictEntries NOTIFY changed)
    Q_PROPERTY(int stagedCount READ stagedCount NOTIFY changed)
    Q_PROPERTY(QString operationPhase READ operationPhase NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString details READ details NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString successMessage READ successMessage NOTIFY changed)
    Q_PROPERTY(QString diffPath READ diffPath NOTIFY diffChanged)
    Q_PROPERTY(bool diffStaged READ diffStaged NOTIFY diffChanged)
    Q_PROPERTY(QString diffText READ diffText NOTIFY diffChanged)
    Q_PROPERTY(bool diffBinary READ diffBinary NOTIFY diffChanged)
    Q_PROPERTY(bool diffTruncated READ diffTruncated NOTIFY diffChanged)
    Q_PROPERTY(bool statusValid READ statusValid NOTIFY changed)
    Q_PROPERTY(QString repoPath READ repoPath NOTIFY changed)
    Q_PROPERTY(bool canCommit READ canCommit NOTIFY changed)
    Q_PROPERTY(bool canPush READ canPush NOTIFY changed)
    Q_PROPERTY(bool canFetch READ canFetch NOTIFY changed)

public:
    static constexpr const char *PhaseIdle = "Idle";
    static constexpr const char *PhaseRefreshing = "Refreshing";
    static constexpr const char *PhaseStaging = "Staging";
    static constexpr const char *PhaseUnstaging = "Unstaging";
    static constexpr const char *PhaseCommitting = "Committing";
    static constexpr const char *PhaseFetching = "Fetching";
    static constexpr const char *PhasePushing = "Pushing";
    static constexpr const char *PhaseDiffing = "Diffing";
    static constexpr const char *PhaseError = "Error";

    explicit GitStatusModel(QObject *parent = nullptr);
    ~GitStatusModel() override;

    void setRepoPath(const QString &repoPath);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void stagePaths(const QStringList &paths);
    Q_INVOKABLE void unstagePaths(const QStringList &paths);
    Q_INVOKABLE void loadDiff(const QString &path, bool staged);
    Q_INVOKABLE void clearDiff();
    Q_INVOKABLE void commit(const QString &message);
    Q_INVOKABLE void fetch();
    Q_INVOKABLE void push();
    Q_INVOKABLE QVariantMap commitPreview() const;
    Q_INVOKABLE void retranslateUi();

    bool available() const { return m_available; }
    QString statusLabel() const;
    bool clean() const { return m_clean; }
    QString branch() const { return m_branch; }
    QString lastCommitHash() const { return m_lastHash; }
    QString lastCommitSubject() const { return m_lastSubject; }
    QString headSummaryText() const;
    QStringList changedFiles() const { return m_files; }
    int changedFileCount() const { return m_files.size(); }
    QString workingTreeLabel() const;
    QString pushStatusLabel() const { return m_pushStatusLabel; }
    QString upstream() const { return m_upstream; }
    int aheadCount() const { return m_ahead; }
    int behindCount() const { return m_behind; }
    bool detachedHead() const { return m_detachedHead; }
    bool hasConflicts() const { return m_hasConflicts; }
    bool hasUpstream() const { return !m_upstream.isEmpty(); }
    QVariantList stagedEntries() const { return m_staged; }
    QVariantList unstagedEntries() const { return m_unstaged; }
    QVariantList untrackedEntries() const { return m_untracked; }
    QVariantList conflictEntries() const { return m_conflicts; }
    int stagedCount() const { return m_staged.size(); }
    QString operationPhase() const { return m_phase; }
    bool busy() const { return m_busy; }
    QString details() const { return m_details; }
    QString error() const { return m_error; }
    QString successMessage() const { return m_successMessage; }
    QString diffPath() const { return m_diffPath; }
    bool diffStaged() const { return m_diffStaged; }
    QString diffText() const { return m_diffText; }
    bool diffBinary() const { return m_diffBinary; }
    bool diffTruncated() const { return m_diffTruncated; }
    bool statusValid() const { return m_statusValid; }
    QString repoPath() const { return m_repoPath; }
    bool canCommit() const;
    bool canPush() const;
    bool canFetch() const;

    // --- testable pure helpers ---
    static QStringList parsePorcelain(const QByteArray &output); // legacy v1 lines
    static QVariantList parsePorcelainV2Z(const QByteArray &output);
    static QStringList snapshotPathsFromEntries(const QVariantList &staged,
                                               const QVariantList &unstaged,
                                               const QVariantList &untracked,
                                               const QVariantList &conflicts);
    static bool isSafeRelativeRepoPath(const QString &path);
    static QStringList filterPathsAgainstSnapshot(const QStringList &requested,
                                                  const QSet<QString> &snapshot,
                                                  QString *errorOut);
    static QStringList buildStageArgv(const QStringList &safePaths);
    static QStringList buildUnstageArgv(const QStringList &safePaths);
    static QStringList buildDiffArgv(const QString &safePath, bool staged);
    static QStringList buildCommitArgv(const QString &message);
    static QStringList buildPushArgv();
    static QStringList buildFetchArgv();
    static bool commitMessageValid(const QString &message, QString *errorOut = nullptr);
    static bool pushArgvIsSafe(const QStringList &argv);
    static QString statusCodeLabel(QChar code);
    static QString repositorySummary(bool available, bool clean, int fileCount);
    static QString headSummary(const QString &hash, const QString &subject);
    static QString formatPushStatus(bool available, bool detached, const QString &upstream,
                                    int ahead, int behind);
    static bool parseAheadBehind(const QByteArray &output, int *aheadOut, int *behindOut);
    static QString classifyCommitFailure(const QByteArray &stderrBytes);
    static QString classifyPushFailure(const QByteArray &stderrBytes);
    static QString truncateDiffOutput(const QByteArray &raw, int maxBytes, int maxLines,
                                      bool *truncatedOut, bool *binaryOut);
    static bool entryListContainsPath(const QVariantList &entries, const QString &path);
    // Clean only when a valid status snapshot exists and all buckets are empty.
    static bool isWorkingTreeClean(bool statusValid, int staged, int unstaged, int untracked,
                                   int conflicts);
    static QString workingTreeLabelFor(bool statusValid, bool refreshing, bool clean, int fileCount);
    // Simulate refresh completion rules (status authoritative; metadata optional).
    static void applyRefreshStatusBytes(const QByteArray &porcelainV2z, bool *statusValidOut,
                                        bool *cleanOut, int *fileCountOut, int *stagedOut,
                                        int *unstagedOut, int *untrackedOut, int *conflictsOut);

signals:
    void changed();
    void diffChanged();
    void operationFinished(bool ok, const QString &message);

private:
    enum class Op {
        None,
        Refresh,
        Stage,
        Unstage,
        Diff,
        Commit,
        Fetch,
        Push
    };

    void setBusy(bool busy);
    void setPhase(const QString &phase);
    void appendDetails(const QString &chunk);
    void clearTransientMessages();
    bool ensureIdleFor(const QString &action);
    void startGit(Op op, const QStringList &args);
    void onProcessFinished(int exitCode, QProcess::ExitStatus status);
    void onProcessErrorOccurred(QProcess::ProcessError error);
    void finishRefresh(int exitCode, const QByteArray &stdoutBytes, const QByteArray &stderrBytes);
    void finishMutatingOp(Op op, int exitCode, const QByteArray &stdoutBytes,
                          const QByteArray &stderrBytes);
    void finishDiff(int exitCode, const QByteArray &stdoutBytes, const QByteArray &stderrBytes);
    void applyParsedEntries(const QVariantList &parsed);
    void rebuildSnapshotPaths();
    QSet<QString> currentSnapshot() const;
    void refreshUpstreamFields(const QByteArray &upstreamOut, bool upstreamOk,
                               const QByteArray &aheadBehindOut, bool aheadOk);
    void killActiveProcess();
    void finalizeIdle();
    bool processIsRunning() const;

    QProcess *m_process = nullptr;
    Op m_op = Op::None;
    int m_opGeneration = 0;
    QString m_repoPath;
    QString m_error;
    QString m_successMessage;
    QString m_details;
    QString m_phase = QString::fromLatin1(PhaseIdle);
    bool m_busy = false;
    bool m_available = false;
    bool m_statusValid = false;
    bool m_clean = false; // never default to Clean before a valid snapshot
    bool m_detachedHead = false;
    bool m_hasConflicts = false;
    QString m_branch;
    QString m_lastHash;
    QString m_lastSubject;
    QString m_upstream;
    QString m_pushStatusLabel;
    int m_ahead = 0;
    int m_behind = 0;
    QStringList m_files;
    QVariantList m_staged;
    QVariantList m_unstaged;
    QVariantList m_untracked;
    QVariantList m_conflicts;
    QSet<QString> m_snapshotPaths;
    QString m_diffPath;
    bool m_diffStaged = false;
    QString m_diffText;
    bool m_diffBinary = false;
    bool m_diffTruncated = false;
    QString m_pendingCommitMessage;
    bool m_refreshAfterCommit = false;
};
