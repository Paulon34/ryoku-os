#include "GitStatusModel.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QRegularExpression>

Q_LOGGING_CATEGORY(lcGit, "ryoku.settings.git")

namespace {
constexpr int kDiffMaxBytes = 64 * 1024;
constexpr int kDiffMaxLines = 800;
constexpr int kDetailsMax = 16000;

QVariantMap makeEntry(const QString &path, QChar code, const QString &section,
                      const QString &origPath = QString())
{
    QVariantMap m;
    m.insert(QStringLiteral("path"), path);
    m.insert(QStringLiteral("code"), QString(code));
    m.insert(QStringLiteral("label"), GitStatusModel::statusCodeLabel(code));
    m.insert(QStringLiteral("section"), section);
    if (!origPath.isEmpty())
        m.insert(QStringLiteral("origPath"), origPath);
    m.insert(QStringLiteral("conflicted"), code == QLatin1Char('U'));
    return m;
}

QStringList splitNul(const QByteArray &data)
{
    QStringList out;
    int start = 0;
    for (int i = 0; i < data.size(); ++i) {
        if (data.at(i) == '\0') {
            out.append(QString::fromUtf8(data.mid(start, i - start)));
            start = i + 1;
        }
    }
    if (start < data.size())
        out.append(QString::fromUtf8(data.mid(start)));
    while (!out.isEmpty() && out.last().isEmpty())
        out.removeLast();
    return out;
}

bool parseOrdinaryOrRenameFields(const QString &record, QChar *xy0, QChar *xy1, bool *renamed,
                                 QString *scoreOut)
{
    // "1 XY …" or "2 XY …"
    if (record.size() < 4)
        return false;
    const QChar kind = record.at(0);
    if (kind != QLatin1Char('1') && kind != QLatin1Char('2') && kind != QLatin1Char('u'))
        return false;
    // After "1 " or "2 " or "u ": XY is next two chars, then space.
    int xyPos = 2;
    if (record.at(1) != QLatin1Char(' '))
        return false;
    if (record.size() < xyPos + 2)
        return false;
    *xy0 = record.at(xyPos);
    *xy1 = record.at(xyPos + 1);
    *renamed = (kind == QLatin1Char('2'));
    if (scoreOut)
        scoreOut->clear();
    return true;
}
} // namespace

GitStatusModel::GitStatusModel(QObject *parent)
    : QObject(parent)
{
}

GitStatusModel::~GitStatusModel()
{
    killActiveProcess();
}

void GitStatusModel::setRepoPath(const QString &repoPath)
{
    if (m_repoPath == repoPath)
        return;
    m_repoPath = repoPath;
    refresh();
}

QString GitStatusModel::statusLabel() const
{
    if (!m_available && !m_statusValid)
        return tr("Unavailable");
    if (m_busy && m_phase == QLatin1String(PhaseRefreshing) && !m_statusValid)
        return tr("Refreshing…");
    if (m_detachedHead)
        return tr("Detached HEAD");
    if (m_hasConflicts)
        return tr("Conflicts");
    if (!m_statusValid)
        return tr("Unavailable");
    return m_clean ? tr("Clean") : tr("Modified");
}

QString GitStatusModel::headSummaryText() const
{
    return headSummary(m_lastHash, m_lastSubject);
}

QString GitStatusModel::workingTreeLabel() const
{
    return workingTreeLabelFor(m_statusValid,
                               m_busy && m_phase == QLatin1String(PhaseRefreshing),
                               m_clean,
                               m_files.size());
}

bool GitStatusModel::canCommit() const
{
    return m_available && !m_busy && !m_detachedHead && !m_hasConflicts && !m_staged.isEmpty();
}

bool GitStatusModel::canPush() const
{
    return m_available && !m_busy && !m_detachedHead && hasUpstream();
}

bool GitStatusModel::canFetch() const
{
    return m_available && !m_busy && !m_detachedHead;
}

QVariantMap GitStatusModel::commitPreview() const
{
    QVariantMap out;
    out.insert(QStringLiteral("canCommit"), canCommit());
    out.insert(QStringLiteral("stagedCount"), m_staged.size());
    QStringList paths;
    paths.reserve(m_staged.size());
    for (const QVariant &v : m_staged)
        paths.append(v.toMap().value(QStringLiteral("path")).toString());
    out.insert(QStringLiteral("stagedPaths"), paths);
    if (m_detachedHead)
        out.insert(QStringLiteral("error"), QStringLiteral("Detached HEAD — commit disabled"));
    else if (m_hasConflicts)
        out.insert(QStringLiteral("error"),
                   QStringLiteral("Resolve conflicts outside Ryoku Settings before committing."));
    else if (m_staged.isEmpty())
        out.insert(QStringLiteral("error"), QStringLiteral("No staged files"));
    return out;
}

QStringList GitStatusModel::parsePorcelain(const QByteArray &output)
{
    QStringList files;
    const QList<QByteArray> lines = output.split('\n');
    for (const QByteArray &line : lines) {
        if (line.size() < 4)
            continue;
        files.append(QString::fromUtf8(line.mid(3).trimmed()));
    }
    files.removeAll(QString());
    return files;
}

QString GitStatusModel::statusCodeLabel(QChar code)
{
    switch (code.toLatin1()) {
    case 'M':
        return QStringLiteral("modified");
    case 'A':
        return QStringLiteral("added");
    case 'D':
        return QStringLiteral("deleted");
    case 'R':
        return QStringLiteral("renamed");
    case 'C':
        return QStringLiteral("copied");
    case 'T':
        return QStringLiteral("typechange");
    case '?':
        return QStringLiteral("untracked");
    case 'U':
        return QStringLiteral("conflict");
    case '!':
        return QStringLiteral("ignored");
    default:
        return QStringLiteral("changed");
    }
}

QVariantList GitStatusModel::parsePorcelainV2Z(const QByteArray &output)
{
    QVariantList out;
    const QStringList tokens = splitNul(output);
    int i = 0;
    while (i < tokens.size()) {
        const QString &tok = tokens.at(i);
        if (tok.isEmpty()) {
            ++i;
            continue;
        }

        if (tok.startsWith(QLatin1Char('?'))) {
            // "? <path>" as one token when -z (path may contain spaces)
            QString path = tok.mid(1).trimmed();
            if (path.startsWith(QLatin1Char(' ')))
                path = path.mid(1);
            if (!path.isEmpty())
                out.append(makeEntry(path, QLatin1Char('?'), QStringLiteral("untracked")));
            ++i;
            continue;
        }
        if (tok.startsWith(QLatin1Char('!'))) {
            ++i;
            continue; // ignored
        }

        QChar x;
        QChar y;
        bool renamed = false;
        if (!parseOrdinaryOrRenameFields(tok, &x, &y, &renamed, nullptr)) {
            ++i;
            continue;
        }

        const bool unmerged = tok.startsWith(QLatin1Char('u'));
        // Path is the last whitespace-separated field in the header token for v2 -z:
        // Ordinary/unmerged: fields then path (path itself may contain spaces — but with -z,
        // path is part of the same NUL field and is the substring after the last of the
        // fixed metadata columns).
        // Format: "1 XY N... mH mI mW hH hI path"
        // Rename: "2 XY N... mH mI mW hH hI R100 path" then next NUL token = origPath
        QString path;
        QString origPath;
        {
            // Split carefully: first 8 (ordinary) or 9 (rename) space-separated fields,
            // remainder is path (may contain spaces).
            const int expectedFields = renamed ? 9 : (unmerged ? 10 : 8);
            int field = 0;
            int pos = 0;
            while (pos < tok.size() && field < expectedFields) {
                while (pos < tok.size() && tok.at(pos) == QLatin1Char(' '))
                    ++pos;
                while (pos < tok.size() && tok.at(pos) != QLatin1Char(' '))
                    ++pos;
                ++field;
            }
            while (pos < tok.size() && tok.at(pos) == QLatin1Char(' '))
                ++pos;
            path = tok.mid(pos);
        }

        if (renamed) {
            ++i;
            if (i < tokens.size())
                origPath = tokens.at(i);
        }

        if (path.isEmpty()) {
            ++i;
            continue;
        }

        if (unmerged) {
            out.append(makeEntry(path, QLatin1Char('U'), QStringLiteral("conflict"), origPath));
        } else {
            if (x != QLatin1Char('.') && x != QLatin1Char(' ')) {
                QChar code = (x == QLatin1Char('R') || renamed) ? QLatin1Char('R') : x;
                if (x == QLatin1Char('C'))
                    code = QLatin1Char('C');
                out.append(makeEntry(path, code, QStringLiteral("staged"), origPath));
            }
            if (y != QLatin1Char('.') && y != QLatin1Char(' ')) {
                QChar code = y;
                if (y == QLatin1Char('R'))
                    code = QLatin1Char('R');
                out.append(makeEntry(path, code, QStringLiteral("unstaged"), origPath));
            }
        }
        ++i;
    }
    return out;
}

QStringList GitStatusModel::snapshotPathsFromEntries(const QVariantList &staged,
                                                     const QVariantList &unstaged,
                                                     const QVariantList &untracked,
                                                     const QVariantList &conflicts)
{
    QSet<QString> set;
    auto absorb = [&](const QVariantList &list) {
        for (const QVariant &v : list) {
            const QString p = v.toMap().value(QStringLiteral("path")).toString();
            if (!p.isEmpty())
                set.insert(p);
            const QString o = v.toMap().value(QStringLiteral("origPath")).toString();
            if (!o.isEmpty())
                set.insert(o);
        }
    };
    absorb(staged);
    absorb(unstaged);
    absorb(untracked);
    absorb(conflicts);
    QStringList out = set.values();
    out.sort();
    return out;
}

bool GitStatusModel::isSafeRelativeRepoPath(const QString &path)
{
    if (path.isEmpty())
        return false;
    if (path.contains(QChar('\0')))
        return false;
    if (path.startsWith(QLatin1Char('/')))
        return false;
    if (path.contains(QLatin1Char('\\')))
        return false;
    // Reject any .. segment
    const QStringList parts = path.split(QLatin1Char('/'), Qt::KeepEmptyParts);
    for (const QString &p : parts) {
        if (p.isEmpty() || p == QLatin1String(".") || p == QLatin1String(".."))
            return false;
    }
    return true;
}

QStringList GitStatusModel::filterPathsAgainstSnapshot(const QStringList &requested,
                                                       const QSet<QString> &snapshot,
                                                       QString *errorOut)
{
    if (errorOut)
        errorOut->clear();
    QStringList out;
    out.reserve(requested.size());
    QSet<QString> seen;
    for (const QString &raw : requested) {
        const QString path = raw.trimmed();
        if (!isSafeRelativeRepoPath(path)) {
            if (errorOut)
                *errorOut = QStringLiteral("Rejected unsafe path: %1").arg(path);
            return {};
        }
        if (!snapshot.contains(path)) {
            if (errorOut)
                *errorOut = QStringLiteral("Path not in current status snapshot: %1").arg(path);
            return {};
        }
        if (seen.contains(path))
            continue;
        seen.insert(path);
        out.append(path);
    }
    if (out.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("No paths selected");
        return {};
    }
    return out;
}

QStringList GitStatusModel::buildStageArgv(const QStringList &safePaths)
{
    QStringList args{QStringLiteral("add"), QStringLiteral("--")};
    args.append(safePaths);
    return args;
}

QStringList GitStatusModel::buildUnstageArgv(const QStringList &safePaths)
{
    QStringList args{QStringLiteral("restore"), QStringLiteral("--staged"), QStringLiteral("--")};
    args.append(safePaths);
    return args;
}

QStringList GitStatusModel::buildDiffArgv(const QString &safePath, bool staged)
{
    if (staged)
        return {QStringLiteral("diff"), QStringLiteral("--cached"), QStringLiteral("--"), safePath};
    return {QStringLiteral("diff"), QStringLiteral("--"), safePath};
}

QStringList GitStatusModel::buildCommitArgv(const QString &message)
{
    return {QStringLiteral("commit"), QStringLiteral("-m"), message};
}

QStringList GitStatusModel::buildPushArgv()
{
    return {QStringLiteral("push")};
}

QStringList GitStatusModel::buildFetchArgv()
{
    return {QStringLiteral("fetch")};
}

bool GitStatusModel::commitMessageValid(const QString &message, QString *errorOut)
{
    const QString t = message.trimmed();
    if (t.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("Commit message is empty");
        return false;
    }
    if (t.size() > 4000) {
        if (errorOut)
            *errorOut = QStringLiteral("Commit message too long");
        return false;
    }
    return true;
}

bool GitStatusModel::pushArgvIsSafe(const QStringList &argv)
{
    if (argv.isEmpty() || argv.at(0) != QLatin1String("push"))
        return false;
    for (const QString &a : argv) {
        if (a == QLatin1String("--force") || a == QLatin1String("-f")
            || a == QLatin1String("--force-with-lease") || a == QLatin1String("--force-if-includes")
            || a == QLatin1String("--all") || a == QLatin1String("--mirror")
            || a == QLatin1String("--tags") || a == QLatin1String("--delete")
            || a.startsWith(QLatin1String("--force")))
            return false;
    }
    return true;
}

QString GitStatusModel::repositorySummary(bool available, bool clean, int fileCount)
{
    if (!available)
        return QCoreApplication::translate("GitStatusModel", "Unavailable");
    if (clean)
        return QCoreApplication::translate("GitStatusModel", "Clean");
    if (fileCount == 1)
        return QCoreApplication::translate("GitStatusModel", "Modified · 1 file");
    return QCoreApplication::translate("GitStatusModel", "Modified · %1 files").arg(fileCount);
}

QString GitStatusModel::headSummary(const QString &hash, const QString &subject)
{
    if (hash.isEmpty())
        return QCoreApplication::translate("GitStatusModel", "Unavailable");
    if (subject.isEmpty())
        return hash;
    return hash + QLatin1Char(' ') + subject;
}

QString GitStatusModel::formatPushStatus(bool available, bool detached, const QString &upstream,
                                         int ahead, int behind)
{
    if (!available)
        return QCoreApplication::translate("GitStatusModel", "Unavailable");
    if (detached)
        return QCoreApplication::translate("GitStatusModel", "Detached HEAD");
    if (upstream.isEmpty())
        return QCoreApplication::translate("GitStatusModel", "No upstream configured");
    if (ahead == 0 && behind == 0)
        return QCoreApplication::translate("GitStatusModel", "Up to date");
    if (ahead > 0 && behind == 0) {
        if (ahead == 1)
            return QCoreApplication::translate("GitStatusModel", "1 commit ahead");
        return QCoreApplication::translate("GitStatusModel", "%1 commits ahead").arg(ahead);
    }
    if (ahead == 0 && behind > 0) {
        if (behind == 1)
            return QCoreApplication::translate("GitStatusModel", "1 commit behind");
        return QCoreApplication::translate("GitStatusModel", "%1 commits behind").arg(behind);
    }
    return QCoreApplication::translate("GitStatusModel", "%1 ahead · %2 behind")
        .arg(ahead)
        .arg(behind);
}

bool GitStatusModel::parseAheadBehind(const QByteArray &output, int *aheadOut, int *behindOut)
{
    if (aheadOut)
        *aheadOut = 0;
    if (behindOut)
        *behindOut = 0;
    const QString s = QString::fromUtf8(output).trimmed();
    if (s.isEmpty())
        return false;
    const QStringList parts = s.split(QRegularExpression(QStringLiteral("[\\s\\t]+")),
                                      Qt::SkipEmptyParts);
    if (parts.size() < 2)
        return false;
    bool okA = false;
    bool okB = false;
    const int a = parts.at(0).toInt(&okA);
    const int b = parts.at(1).toInt(&okB);
    if (!okA || !okB || a < 0 || b < 0)
        return false;
    if (aheadOut)
        *aheadOut = a;
    if (behindOut)
        *behindOut = b;
    return true;
}

QString GitStatusModel::classifyCommitFailure(const QByteArray &stderrBytes)
{
    const QString err = QString::fromUtf8(stderrBytes);
    const QString lower = err.toLower();
    if (lower.contains(QLatin1String("author identity unknown"))
        || lower.contains(QLatin1String("please tell me who you are"))
        || lower.contains(QLatin1String("empty ident name"))) {
        return QStringLiteral(
            "Git user identity is not configured.\n"
            "Set user.name and user.email (global or local), then retry.");
    }
    if (lower.contains(QLatin1String("conflict"))
        || lower.contains(QLatin1String("you are in the middle of"))) {
        return QStringLiteral("Resolve conflicts outside Ryoku Settings before committing.");
    }
    if (lower.contains(QLatin1String("nothing to commit")))
        return QStringLiteral("Nothing to commit");
    return QStringLiteral("Commit failed");
}

QString GitStatusModel::classifyPushFailure(const QByteArray &stderrBytes)
{
    const QString err = QString::fromUtf8(stderrBytes);
    const QString lower = err.toLower();
    if (lower.contains(QLatin1String("authentication failed"))
        || lower.contains(QLatin1String("permission denied"))
        || lower.contains(QLatin1String("could not read username"))
        || lower.contains(QLatin1String("publickey"))
        || lower.contains(QLatin1String("403"))) {
        return QStringLiteral("Remote authentication failed");
    }
    if (lower.contains(QLatin1String("could not resolve host"))
        || lower.contains(QLatin1String("network is unreachable"))
        || lower.contains(QLatin1String("failed to connect"))
        || lower.contains(QLatin1String("timed out"))) {
        return QStringLiteral("Network unavailable");
    }
    if (lower.contains(QLatin1String("no upstream"))
        || lower.contains(QLatin1String("has no upstream"))) {
        return QStringLiteral("No upstream configured");
    }
    if (lower.contains(QLatin1String("non-fast-forward"))
        || lower.contains(QLatin1String("fetch first"))) {
        return QStringLiteral("Push rejected — remote has divergent commits (fetch/review outside Ryoku)");
    }
    return QStringLiteral("Push failed");
}

QString GitStatusModel::truncateDiffOutput(const QByteArray &raw, int maxBytes, int maxLines,
                                           bool *truncatedOut, bool *binaryOut)
{
    if (truncatedOut)
        *truncatedOut = false;
    if (binaryOut)
        *binaryOut = false;

    if (raw.contains('\0')) {
        if (binaryOut)
            *binaryOut = true;
        return QStringLiteral("Binary file changed");
    }

    const QString text = QString::fromUtf8(raw);
    const QString lower = text.left(200).toLower();
    if (lower.contains(QLatin1String("binary files"))
        || lower.contains(QLatin1String("binary file"))) {
        if (binaryOut)
            *binaryOut = true;
        return QStringLiteral("Binary file changed");
    }

    QString clipped = text;
    bool truncated = false;
    if (clipped.size() > maxBytes) {
        clipped = clipped.left(maxBytes);
        truncated = true;
    }
    const QStringList lines = clipped.split(QLatin1Char('\n'));
    if (lines.size() > maxLines) {
        clipped = QStringList(lines.mid(0, maxLines)).join(QLatin1Char('\n'));
        truncated = true;
    }
    if (truncated) {
        if (truncatedOut)
            *truncatedOut = true;
        clipped += QStringLiteral("\n\n… diff truncated …");
    }
    return clipped;
}

bool GitStatusModel::entryListContainsPath(const QVariantList &entries, const QString &path)
{
    for (const QVariant &v : entries) {
        if (v.toMap().value(QStringLiteral("path")).toString() == path)
            return true;
    }
    return false;
}

bool GitStatusModel::isWorkingTreeClean(bool statusValid, int staged, int unstaged, int untracked,
                                        int conflicts)
{
    if (!statusValid)
        return false;
    return staged == 0 && unstaged == 0 && untracked == 0 && conflicts == 0;
}

QString GitStatusModel::workingTreeLabelFor(bool statusValid, bool refreshing, bool clean,
                                            int fileCount)
{
    if (refreshing && !statusValid)
        return QCoreApplication::translate("GitStatusModel", "Refreshing…");
    if (!statusValid)
        return QCoreApplication::translate("GitStatusModel", "Unavailable");
    if (clean)
        return QCoreApplication::translate("GitStatusModel", "Clean");
    if (fileCount == 1)
        return QCoreApplication::translate("GitStatusModel", "Modified · 1 file");
    return QCoreApplication::translate("GitStatusModel", "Modified · %1 files").arg(fileCount);
}

void GitStatusModel::retranslateUi()
{
    m_pushStatusLabel = formatPushStatus(m_available, m_detachedHead, m_upstream, m_ahead, m_behind);
    emit changed();
}

void GitStatusModel::applyRefreshStatusBytes(const QByteArray &porcelainV2z, bool *statusValidOut,
                                             bool *cleanOut, int *fileCountOut, int *stagedOut,
                                             int *unstagedOut, int *untrackedOut, int *conflictsOut)
{
    const QVariantList parsed = parsePorcelainV2Z(porcelainV2z);
    int staged = 0;
    int unstaged = 0;
    int untracked = 0;
    int conflicts = 0;
    QSet<QString> paths;
    for (const QVariant &v : parsed) {
        const QVariantMap m = v.toMap();
        const QString section = m.value(QStringLiteral("section")).toString();
        const QString path = m.value(QStringLiteral("path")).toString();
        if (section == QLatin1String("staged"))
            ++staged;
        else if (section == QLatin1String("unstaged"))
            ++unstaged;
        else if (section == QLatin1String("untracked"))
            ++untracked;
        else if (section == QLatin1String("conflict"))
            ++conflicts;
        if (!path.isEmpty())
            paths.insert(path);
    }
    if (statusValidOut)
        *statusValidOut = true;
    if (stagedOut)
        *stagedOut = staged;
    if (unstagedOut)
        *unstagedOut = unstaged;
    if (untrackedOut)
        *untrackedOut = untracked;
    if (conflictsOut)
        *conflictsOut = conflicts;
    if (fileCountOut)
        *fileCountOut = paths.size();
    if (cleanOut)
        *cleanOut = isWorkingTreeClean(true, staged, unstaged, untracked, conflicts);
}

void GitStatusModel::setBusy(bool busy)
{
    m_busy = busy;
}

void GitStatusModel::setPhase(const QString &phase)
{
    m_phase = phase;
}

void GitStatusModel::appendDetails(const QString &chunk)
{
    m_details += chunk;
    if (m_details.size() > kDetailsMax)
        m_details = m_details.right(kDetailsMax);
}

void GitStatusModel::clearTransientMessages()
{
    m_error.clear();
    m_successMessage.clear();
}

void GitStatusModel::killActiveProcess()
{
    if (!m_process)
        return;
    if (m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(1000);
    }
}

bool GitStatusModel::processIsRunning() const
{
    return m_process && m_process->state() != QProcess::NotRunning;
}

bool GitStatusModel::ensureIdleFor(const QString &action)
{
    if (m_busy || processIsRunning()) {
        m_error = QStringLiteral("Git busy — wait for %1 to finish before %2")
                      .arg(m_phase, action);
        emit changed();
        return false;
    }
    if (m_repoPath.isEmpty()) {
        m_error = QStringLiteral("Repository path unavailable");
        emit changed();
        return false;
    }
    return true;
}

void GitStatusModel::finalizeIdle()
{
    setBusy(false);
    setPhase(QString::fromLatin1(PhaseIdle));
}

QSet<QString> GitStatusModel::currentSnapshot() const
{
    return m_snapshotPaths;
}

void GitStatusModel::rebuildSnapshotPaths()
{
    const QStringList paths =
        snapshotPathsFromEntries(m_staged, m_unstaged, m_untracked, m_conflicts);
    m_snapshotPaths = QSet<QString>(paths.begin(), paths.end());
}

void GitStatusModel::applyParsedEntries(const QVariantList &parsed)
{
    m_staged.clear();
    m_unstaged.clear();
    m_untracked.clear();
    m_conflicts.clear();
    m_hasConflicts = false;
    QStringList files;
    QSet<QString> seenFiles;

    for (const QVariant &v : parsed) {
        const QVariantMap m = v.toMap();
        const QString section = m.value(QStringLiteral("section")).toString();
        const QString path = m.value(QStringLiteral("path")).toString();
        if (section == QLatin1String("staged"))
            m_staged.append(m);
        else if (section == QLatin1String("unstaged"))
            m_unstaged.append(m);
        else if (section == QLatin1String("untracked"))
            m_untracked.append(m);
        else if (section == QLatin1String("conflict")) {
            m_conflicts.append(m);
            m_hasConflicts = true;
        }
        if (!path.isEmpty() && !seenFiles.contains(path)) {
            seenFiles.insert(path);
            files.append(path);
        }
    }
    m_files = files;
    m_statusValid = true;
    m_clean = isWorkingTreeClean(true, m_staged.size(), m_unstaged.size(), m_untracked.size(),
                                 m_conflicts.size());
    rebuildSnapshotPaths();
}

void GitStatusModel::startGit(Op op, const QStringList &args)
{
    if (processIsRunning()) {
        qWarning(lcGit) << "[git] refused start — previous process still running"
                        << "phase" << m_phase << "requested" << args;
        m_error = QStringLiteral("Git busy — previous process still running");
        setPhase(QString::fromLatin1(PhaseError));
        setBusy(false);
        emit changed();
        return;
    }

    if (!m_process) {
        m_process = new QProcess(this);
        // Never drain stdout here for Refresh/Diff — porcelain/diff bytes are NUL-sensitive
        // and must be read intact in onProcessFinished.
        connect(m_process, &QProcess::readyReadStandardOutput, this, [this]() {
            if (m_op == Op::Diff || m_op == Op::Refresh)
                return;
            appendDetails(QString::fromUtf8(m_process->readAllStandardOutput()));
            emit changed();
        });
        connect(m_process, &QProcess::readyReadStandardError, this, [this]() {
            appendDetails(QString::fromUtf8(m_process->readAllStandardError()));
            emit changed();
        });
        connect(m_process, &QProcess::errorOccurred, this, &GitStatusModel::onProcessErrorOccurred);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                &GitStatusModel::onProcessFinished);
    }

    ++m_opGeneration;
    const int gen = m_opGeneration;
    m_process->setProperty("ryokuGitGen", gen);
    m_op = op;
    setBusy(true);
    if (op != Op::Refresh)
        clearTransientMessages();

    const QString opName = args.isEmpty() ? QStringLiteral("(empty)") : args.join(QLatin1Char(' '));
    qInfo(lcGit) << "[git] start" << opName << "gen" << gen;
    appendDetails(QStringLiteral("\n$ git %1\n").arg(opName));

    m_process->setProgram(QStringLiteral("git"));
    m_process->setArguments(args);
    m_process->setWorkingDirectory(m_repoPath);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->start();
    if (!m_process->waitForStarted(3000)) {
        qWarning(lcGit) << "[git] error start failed" << m_process->errorString();
        m_op = Op::None;
        finalizeIdle();
        setPhase(QString::fromLatin1(PhaseError));
        m_error = QStringLiteral("Failed to start git: %1").arg(m_process->errorString());
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    emit changed();
}

void GitStatusModel::refresh()
{
    // Coalesce duplicate refresh while one is in flight — do not sticky-error the UI.
    if (m_busy || processIsRunning()) {
        if (m_phase == QLatin1String(PhaseRefreshing)) {
            qInfo(lcGit) << "[git] refresh coalesced — already Refreshing";
            return;
        }
        if (!ensureIdleFor(QStringLiteral("refresh")))
            return;
    } else if (m_repoPath.isEmpty()) {
        m_error = QStringLiteral("Repository path unavailable");
        emit changed();
        return;
    }
    if (m_repoPath.isEmpty()) {
        m_error = QStringLiteral("Repository path unavailable");
        emit changed();
        return;
    }
    setPhase(QString::fromLatin1(PhaseRefreshing));
    qInfo(lcGit) << "[git] start refresh";
    startGit(Op::Refresh,
             {QStringLiteral("status"), QStringLiteral("--porcelain=v2"), QStringLiteral("-z")});
}

void GitStatusModel::stagePaths(const QStringList &paths)
{
    if (!ensureIdleFor(QStringLiteral("stage")))
        return;
    QString err;
    const QStringList safe = filterPathsAgainstSnapshot(paths, currentSnapshot(), &err);
    if (safe.isEmpty()) {
        m_error = err;
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    setPhase(QString::fromLatin1(PhaseStaging));
    startGit(Op::Stage, buildStageArgv(safe));
}

void GitStatusModel::unstagePaths(const QStringList &paths)
{
    if (!ensureIdleFor(QStringLiteral("unstage")))
        return;
    QString err;
    // Unstage only from staged/conflict snapshot paths that appear staged.
    QSet<QString> allowed;
    for (const QVariant &v : m_staged)
        allowed.insert(v.toMap().value(QStringLiteral("path")).toString());
    for (const QVariant &v : m_conflicts)
        allowed.insert(v.toMap().value(QStringLiteral("path")).toString());
    const QStringList safe = filterPathsAgainstSnapshot(paths, allowed, &err);
    if (safe.isEmpty()) {
        m_error = err.isEmpty() ? QStringLiteral("No staged paths selected") : err;
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    setPhase(QString::fromLatin1(PhaseUnstaging));
    startGit(Op::Unstage, buildUnstageArgv(safe));
}

void GitStatusModel::loadDiff(const QString &path, bool staged)
{
    if (!ensureIdleFor(QStringLiteral("diff")))
        return;
    if (!isSafeRelativeRepoPath(path) || !currentSnapshot().contains(path)) {
        m_error = QStringLiteral("Diff path rejected");
        m_diffPath.clear();
        m_diffText.clear();
        emit diffChanged();
        emit changed();
        return;
    }
    m_diffPath = path;
    m_diffStaged = staged;
    m_diffText.clear();
    m_diffBinary = false;
    m_diffTruncated = false;
    setPhase(QString::fromLatin1(PhaseDiffing));
    startGit(Op::Diff, buildDiffArgv(path, staged));
}

void GitStatusModel::clearDiff()
{
    m_diffPath.clear();
    m_diffText.clear();
    m_diffBinary = false;
    m_diffTruncated = false;
    m_diffStaged = false;
    emit diffChanged();
}

void GitStatusModel::commit(const QString &message)
{
    if (!ensureIdleFor(QStringLiteral("commit")))
        return;
    QString err;
    if (!commitMessageValid(message, &err)) {
        m_error = err;
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    if (m_detachedHead) {
        m_error = QStringLiteral("Detached HEAD — commit disabled in Ryoku Settings");
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    if (m_hasConflicts) {
        m_error = QStringLiteral("Resolve conflicts outside Ryoku Settings before committing.");
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    if (m_staged.isEmpty()) {
        m_error = QStringLiteral("No staged files");
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    m_pendingCommitMessage = message.trimmed();
    setPhase(QString::fromLatin1(PhaseCommitting));
    startGit(Op::Commit, buildCommitArgv(m_pendingCommitMessage));
}

void GitStatusModel::fetch()
{
    if (!ensureIdleFor(QStringLiteral("fetch")))
        return;
    if (m_detachedHead) {
        m_error = QStringLiteral("Fetch disabled while Detached HEAD");
        emit changed();
        return;
    }
    setPhase(QString::fromLatin1(PhaseFetching));
    startGit(Op::Fetch, buildFetchArgv());
}

void GitStatusModel::push()
{
    if (!ensureIdleFor(QStringLiteral("push")))
        return;
    if (m_detachedHead) {
        m_error = QStringLiteral("Push disabled while Detached HEAD");
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    if (!hasUpstream()) {
        m_error = QStringLiteral("No upstream configured");
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }
    const QStringList argv = buildPushArgv();
    if (!pushArgvIsSafe(argv)) {
        m_error = QStringLiteral("Internal: unsafe push argv blocked");
        setPhase(QString::fromLatin1(PhaseError));
        emit changed();
        return;
    }
    setPhase(QString::fromLatin1(PhasePushing));
    startGit(Op::Push, argv);
}

void GitStatusModel::onProcessErrorOccurred(QProcess::ProcessError error)
{
    if (!m_process)
        return;
    const int gen = m_process->property("ryokuGitGen").toInt();
    if (gen != m_opGeneration)
        return;
    qWarning(lcGit) << "[git] error" << static_cast<int>(error) << m_process->errorString()
                    << "op" << static_cast<int>(m_op);
    if (error == QProcess::FailedToStart && m_op != Op::None) {
        m_op = Op::None;
        finalizeIdle();
        setPhase(QString::fromLatin1(PhaseError));
        m_error = QStringLiteral("Failed to start git (%1)").arg(m_process->errorString());
        appendDetails(m_error + QLatin1Char('\n'));
        emit changed();
        emit operationFinished(false, m_error);
    }
}

void GitStatusModel::onProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_process)
        return;
    const int gen = m_process->property("ryokuGitGen").toInt();
    if (gen != m_opGeneration)
        return;

    const Op op = m_op;
    // Read remaining bytes AFTER determining op — Refresh/Diff must not have been drained.
    const QByteArray stdoutBytes = m_process->readAllStandardOutput();
    const QByteArray stderrBytes = m_process->readAllStandardError();
    m_op = Op::None;

    qInfo(lcGit) << "[git] finished" << static_cast<int>(op) << "exit=" << exitCode
                 << "status=" << static_cast<int>(status) << "stdoutBytes=" << stdoutBytes.size();

    if (!stdoutBytes.isEmpty() && op != Op::Diff && op != Op::Refresh)
        appendDetails(QString::fromUtf8(stdoutBytes));
    if (!stderrBytes.isEmpty())
        appendDetails(QString::fromUtf8(stderrBytes));

    if (status != QProcess::NormalExit) {
        finalizeIdle();
        setPhase(QString::fromLatin1(PhaseError));
        m_error = QStringLiteral("Git process crashed");
        emit changed();
        emit operationFinished(false, m_error);
        return;
    }

    switch (op) {
    case Op::Refresh:
        finishRefresh(exitCode, stdoutBytes, stderrBytes);
        break;
    case Op::Diff:
        finishDiff(exitCode, stdoutBytes, stderrBytes);
        break;
    case Op::Stage:
    case Op::Unstage:
    case Op::Commit:
    case Op::Fetch:
    case Op::Push:
        finishMutatingOp(op, exitCode, stdoutBytes, stderrBytes);
        break;
    case Op::None:
        finalizeIdle();
        emit changed();
        break;
    }
}

void GitStatusModel::finishDiff(int exitCode, const QByteArray &stdoutBytes,
                                const QByteArray &stderrBytes)
{
    finalizeIdle();
    // Empty diff (exit 0) is valid — no changes on that side.
    if (exitCode != 0 && stdoutBytes.isEmpty()) {
        m_diffText = QStringLiteral("Diff unavailable");
        if (!stderrBytes.isEmpty())
            appendDetails(QString::fromUtf8(stderrBytes));
        m_error = QStringLiteral("Diff failed");
        emit diffChanged();
        emit changed();
        return;
    }
    bool truncated = false;
    bool binary = false;
    m_diffText = truncateDiffOutput(stdoutBytes, kDiffMaxBytes, kDiffMaxLines, &truncated, &binary);
    m_diffTruncated = truncated;
    m_diffBinary = binary;
    if (m_diffText.isEmpty() && !binary)
        m_diffText = QStringLiteral("(no differences)");
    emit diffChanged();
    emit changed();
}

void GitStatusModel::refreshUpstreamFields(const QByteArray &upstreamOut, bool upstreamOk,
                                           const QByteArray &aheadBehindOut, bool aheadOk)
{
    m_upstream.clear();
    m_ahead = 0;
    m_behind = 0;
    if (upstreamOk) {
        const QString u = QString::fromUtf8(upstreamOut).trimmed();
        if (!u.isEmpty() && u != QLatin1String("HEAD"))
            m_upstream = u;
    }
    if (aheadOk && !m_upstream.isEmpty())
        parseAheadBehind(aheadBehindOut, &m_ahead, &m_behind);
    m_pushStatusLabel = formatPushStatus(m_available, m_detachedHead, m_upstream, m_ahead, m_behind);
}

void GitStatusModel::finishRefresh(int exitCode, const QByteArray &stdoutBytes,
                                   const QByteArray &stderrBytes)
{
    // Status porcelain is authoritative. Publish it before any metadata reads.
    // Metadata failures must not clear/replace a valid status snapshot.

    auto runQuick = [this](const QStringList &args, bool *ok) -> QByteArray {
        QProcess proc;
        proc.setProgram(QStringLiteral("git"));
        proc.setArguments(args);
        proc.setWorkingDirectory(m_repoPath);
        proc.setProcessChannelMode(QProcess::SeparateChannels);
        proc.start();
        if (!proc.waitForFinished(8000)) {
            proc.kill();
            if (ok)
                *ok = false;
            return {};
        }
        if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
            if (ok)
                *ok = false;
            return {};
        }
        if (ok)
            *ok = true;
        return proc.readAllStandardOutput();
    };

    if (exitCode != 0) {
        finalizeIdle();
        setPhase(QString::fromLatin1(PhaseError));
        m_error = QStringLiteral("git status failed");
        if (!stderrBytes.isEmpty())
            appendDetails(QString::fromUtf8(stderrBytes));
        qWarning(lcGit) << "[git] refresh status failed exit=" << exitCode
                        << "stdoutBytes=" << stdoutBytes.size();
        emit changed();
        return;
    }

    applyParsedEntries(parsePorcelainV2Z(stdoutBytes));
    m_available = true;
    qInfo(lcGit) << "[git] refresh status applied"
                 << "rawBytes=" << stdoutBytes.size()
                 << "staged=" << m_staged.size()
                 << "unstaged=" << m_unstaged.size()
                 << "untracked=" << m_untracked.size()
                 << "conflicts=" << m_conflicts.size()
                 << "files=" << m_files.size()
                 << "clean=" << m_clean;
    // Publish status immediately so UI is not stuck on Refreshing/Clean-default.
    emit changed();

    bool ok = false;
    const QByteArray branchOut =
        runQuick({QStringLiteral("branch"), QStringLiteral("--show-current")}, &ok);
    if (ok) {
        m_branch = QString::fromUtf8(branchOut).trimmed();
        m_detachedHead = m_branch.isEmpty();
    }

    const QByteArray logLine =
        runQuick({QStringLiteral("log"), QStringLiteral("-1"), QStringLiteral("--format=%h%x09%s")},
                 &ok);
    if (ok) {
        const QString s = QString::fromUtf8(logLine).trimmed();
        const int tab = s.indexOf(QLatin1Char('\t'));
        if (tab < 0) {
            m_lastHash = s;
            m_lastSubject.clear();
        } else {
            m_lastHash = s.left(tab);
            m_lastSubject = s.mid(tab + 1);
        }
    }

    bool upOk = false;
    bool abOk = false;
    QByteArray upOut;
    QByteArray abOut;
    if (!m_detachedHead) {
        upOut = runQuick({QStringLiteral("rev-parse"), QStringLiteral("--abbrev-ref"),
                          QStringLiteral("--symbolic-full-name"), QStringLiteral("@{u}")},
                         &upOk);
        if (upOk) {
            abOut = runQuick({QStringLiteral("rev-list"), QStringLiteral("--left-right"),
                              QStringLiteral("--count"), QStringLiteral("HEAD...@{u}")},
                             &abOk);
        }
    }
    // Missing upstream / ahead-behind failure must NOT undo status.
    refreshUpstreamFields(upOut, upOk, abOut, abOk);

    if (m_refreshAfterCommit) {
        m_refreshAfterCommit = false;
        if (!m_lastHash.isEmpty())
            m_successMessage = QStringLiteral("Committed %1").arg(m_lastHash);
    }

    finalizeIdle();
    m_error.clear(); // successful status publish clears sticky busy/auth noise
    qInfo(lcGit) << "[git] refresh complete"
                 << "branch=" << (m_detachedHead ? QStringLiteral("(detached)") : m_branch)
                 << "upstream=" << (m_upstream.isEmpty() ? QStringLiteral("(none)") : m_upstream)
                 << "ahead=" << m_ahead << "behind=" << m_behind
                 << "staged=" << m_staged.size() << "unstaged=" << m_unstaged.size()
                 << "untracked=" << m_untracked.size() << "conflicts=" << m_conflicts.size();
    emit changed();
}

void GitStatusModel::finishMutatingOp(Op op, int exitCode, const QByteArray &stdoutBytes,
                                      const QByteArray &stderrBytes)
{
    Q_UNUSED(stdoutBytes);
    setBusy(false);

    if (exitCode != 0) {
        setPhase(QString::fromLatin1(PhaseError));
        if (op == Op::Commit)
            m_error = classifyCommitFailure(stderrBytes);
        else if (op == Op::Push)
            m_error = classifyPushFailure(stderrBytes);
        else if (op == Op::Fetch)
            m_error = classifyPushFailure(stderrBytes).contains(QLatin1String("Network"))
                          ? QStringLiteral("Network unavailable")
                          : QStringLiteral("Fetch failed");
        else if (op == Op::Stage)
            m_error = QStringLiteral("Stage failed");
        else if (op == Op::Unstage)
            m_error = QStringLiteral("Unstage failed");
        else
            m_error = QStringLiteral("Git operation failed");
        emit changed();
        emit operationFinished(false, m_error);
        // Still refresh to resync snapshot (coalesced if somehow busy).
        refresh();
        return;
    }

    if (op == Op::Commit) {
        m_successMessage = QStringLiteral("Committed");
        m_refreshAfterCommit = true;
    } else if (op == Op::Push) {
        m_refreshAfterCommit = false;
        m_successMessage = m_branch.isEmpty()
                               ? QStringLiteral("Pushed")
                               : QStringLiteral("Pushed %1 to %2")
                                     .arg(m_branch, m_upstream.isEmpty()
                                                       ? QStringLiteral("remote")
                                                       : m_upstream.section(QLatin1Char('/'), 0, 0));
    } else if (op == Op::Fetch) {
        m_refreshAfterCommit = false;
        m_successMessage = QStringLiteral("Fetch complete");
    } else if (op == Op::Stage) {
        m_refreshAfterCommit = false;
        m_successMessage = QStringLiteral("Staged");
    } else if (op == Op::Unstage) {
        m_refreshAfterCommit = false;
        m_successMessage = QStringLiteral("Unstaged");
    }

    emit operationFinished(true, m_successMessage);
    refresh();
}
