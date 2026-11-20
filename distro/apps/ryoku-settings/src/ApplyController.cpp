#include "ApplyController.h"

#include "RepoPath.h"
#include "SettingsStore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QStandardPaths>

// Flake host baked by Nix (modules/ryoku.nix); only used in the bootstrap hint.
#ifndef RYOKU_FLAKE_HOST_DEFAULT
#define RYOKU_FLAKE_HOST_DEFAULT ""
#endif

Q_LOGGING_CATEGORY(lcApply, "ryoku.settings.apply")

namespace {
constexpr auto kMarkerRel = "ryoku/applied-settings-hash";
constexpr auto kHelperPathRel = "ryoku/settings-apply-helper";
constexpr int kMaxLogChars = 512 * 1024;
constexpr int kSha256HexLen = 64;
} // namespace

ApplyController::ApplyController(QObject *parent)
    : QObject(parent)
{
    m_nix = findNix();
    m_pkexec = findPkexec();
    detectHelper();
}

ApplyController::~ApplyController()
{
    if (m_hashProcess) {
        m_hashProcess->kill();
        m_hashProcess->waitForFinished(1000);
    }
    if (m_validateProcess) {
        m_validateProcess->kill();
        m_validateProcess->waitForFinished(1000);
    }
    if (m_privilegedProcess) {
        // Never kill privileged apply mid-activation — wait for natural finish.
        if (m_privilegedProcess->state() != QProcess::NotRunning)
            m_privilegedProcess->waitForFinished(-1);
    }
}

void ApplyController::setRepoPath(const QString &repoPath)
{
    m_repoPath = repoPath;
    watchMarker();
    refresh();
}

void ApplyController::setSettingsStore(SettingsStore *store)
{
    if (m_store == store)
        return;
    if (m_store)
        disconnect(m_store, nullptr, this, nullptr);
    m_store = store;
    if (m_store) {
        connect(m_store, &SettingsStore::changed, this, [this]() {
            requestCurrentHash();
        });
        connect(m_store, &SettingsStore::writeFinished, this, [this](bool ok) {
            if (ok) {
                m_validatedOk = false;
                requestCurrentHash();
            }
        });
    }
}

void ApplyController::setUnsavedDraft(bool unsaved)
{
    if (m_unsavedDraft == unsaved)
        return;
    m_unsavedDraft = unsaved;
    emit changed();
}

void ApplyController::setLockfilePendingRebuild(bool pending)
{
    if (m_lockfilePendingRebuild == pending)
        return;
    m_lockfilePendingRebuild = pending;
    recomputeApplyState();
    emit changed();
}

void ApplyController::retranslateUi()
{
    emit changed();
    emit logChanged();
}

QString ApplyController::statusText() const
{
    if (m_unsavedDraft && m_status == QLatin1String(StatusApplied))
        return tr("Unsaved draft · Applied");
    if (m_unsavedDraft && m_status == QLatin1String(StatusNeedsApply))
        return tr("Unsaved draft · Needs Apply");
    if (m_unsavedDraft && m_status == QLatin1String(StatusIdle))
        return tr("Unsaved draft");
    if (m_unsavedDraft)
        return tr("Unsaved draft · %1").arg(m_status);

    if (m_status == QLatin1String(StatusApplied)) {
        if (m_lockfilePendingRebuild)
            return tr("Settings applied · flake lock pending rebuild");
        return tr("Applied");
    }
    if (m_status == QLatin1String(StatusNeedsApply)) {
        if (m_lockfilePendingRebuild)
            return tr("Needs Apply (flake lock)");
        return tr("Needs Apply");
    }
    if (m_status == QLatin1String(StatusValidating))
        return tr("Validating…");
    if (m_status == QLatin1String(StatusReady))
        return tr("Validated · ready to apply");
    if (m_status == QLatin1String(StatusValidationFailed))
        return tr("Validation Failed");
    if (m_status == QLatin1String(StatusAwaitingAuthorization))
        return tr("Waiting for authorization…");
    if (m_status == QLatin1String(StatusApplying))
        return tr("Applying system configuration…");
    if (m_status == QLatin1String(StatusApplyFailed))
        return tr("Apply Failed");
    if (m_status == QLatin1String(StatusAuthorizationDenied))
        return tr("Authorization denied");
    if (m_status == QLatin1String(StatusAuthorizationError))
        return tr("Authorization error");
    if (m_status == QLatin1String(StatusRollingBack))
        return tr("Rolling back…");
    if (m_status == QLatin1String(StatusRollbackFailed))
        return tr("Rollback Failed");
    if (m_status == QLatin1String(StatusSwitchingGeneration))
        return tr("Switching system generation…");
    if (m_status == QLatin1String(StatusSwitchFailed))
        return tr("Generation switch failed");
    if (m_status == QLatin1String(StatusHashError))
        return tr("Hash error");
    if (m_status == QLatin1String(StatusIdle))
        return tr("Resolving apply state…");
    return m_status;
}

QString ApplyController::bootstrapHint() const
{
    if (m_helperInstalled)
        return {};
    const QString repo = m_repoPath.isEmpty() ? QStringLiteral("<ryoku repo>") : m_repoPath;
    const QString host = QString::fromUtf8(RYOKU_FLAKE_HOST_DEFAULT).trimmed();
    return QStringLiteral(
               "Apply helper is not installed yet. On Debian Modular run:\n"
               "sudo ./distro/scripts/ryoku-bootstrap --apply --user %1 "
               "--profile minimal --compositor hyprland\n"
               "(flake host attr: %2 — repo: %3)")
        .arg(host.isEmpty() ? QStringLiteral("<user>") : host,
             host.isEmpty() ? QStringLiteral("<user>") : host,
             repo);
}

bool ApplyController::canValidate() const
{
    if (m_busy || m_repoPath.isEmpty() || !repoLooksValid())
        return false;
    return m_needsSystemApply || m_needsUserApply || m_lockfilePendingRebuild
           || m_status == QLatin1String(StatusValidationFailed)
           || m_status == QLatin1String(StatusReady)
           || m_status == QLatin1String(StatusNeedsApply)
           || m_status == QLatin1String(StatusAuthorizationDenied)
           || m_status == QLatin1String(StatusAuthorizationError);
}

bool ApplyController::canApply() const
{
    if (m_busy || m_unsavedDraft || !m_helperInstalled)
        return false;
    if (m_pkexec.isEmpty() || m_helperPath.isEmpty())
        return false;
    // Block Apply until flakeDir resolves (Debian: distro/flake).
    if (Ryoku::resolveFlakeDir(m_repoPath).isEmpty())
        return false;
    return (m_needsSystemApply || m_lockfilePendingRebuild)
           && (m_status == QLatin1String(StatusNeedsApply)
               || m_status == QLatin1String(StatusReady)
               || m_status == QLatin1String(StatusAuthorizationDenied)
               || m_status == QLatin1String(StatusAuthorizationError)
               || m_status == QLatin1String(StatusApplyFailed));
}

bool ApplyController::canRollback() const
{
    if (m_busy || !m_helperInstalled || m_pkexec.isEmpty() || m_helperPath.isEmpty())
        return false;
    return m_rollbackAvailable
           && (m_status == QLatin1String(StatusApplied)
               || m_status == QLatin1String(StatusNeedsApply)
               || m_status == QLatin1String(StatusReady)
               || m_status == QLatin1String(StatusSwitchFailed));
}

bool ApplyController::canSwitchGeneration(int generation) const
{
    if (m_busy || !m_helperInstalled || m_pkexec.isEmpty() || m_helperPath.isEmpty())
        return false;
    if (m_unsavedDraft)
        return false;
    if (generation < 1)
        return false;
    const int current = readProfileGenerationNumber();
    if (current > 0 && generation == current)
        return false;
    QString err;
    if (!validateSystemGenerationExists(generation, nullptr, &err))
        return false;
    return m_status == QLatin1String(StatusApplied)
           || m_status == QLatin1String(StatusNeedsApply)
           || m_status == QLatin1String(StatusReady)
           || m_status == QLatin1String(StatusSwitchFailed)
           || m_status == QLatin1String(StatusApplyFailed)
           || m_status == QLatin1String(StatusIdle);
}

QString ApplyController::appliedMarkerPath()
{
    return QStringLiteral("/etc/%1").arg(QString::fromLatin1(kMarkerRel));
}

QString ApplyController::helperPathFile()
{
    return QStringLiteral("/etc/%1").arg(QString::fromLatin1(kHelperPathRel));
}

QString ApplyController::normalizeHash(const QString &raw)
{
    return raw.trimmed();
}

bool ApplyController::isValidSha256Hex(const QString &hash)
{
    if (hash.size() != kSha256HexLen)
        return false;
    static const QRegularExpression re(QStringLiteral("^[0-9a-fA-F]{64}$"));
    return re.match(hash).hasMatch();
}

bool ApplyController::hashesMatch(const QString &current, const QString &applied)
{
    const QString c = normalizeHash(current);
    const QString a = normalizeHash(applied);
    if (!isValidSha256Hex(c) || !isValidSha256Hex(a))
        return false;
    return c.toLower() == a.toLower();
}

QString ApplyController::hashFromNixEvalStdout(const QByteArray &stdoutBytes)
{
    return normalizeHash(QString::fromUtf8(stdoutBytes));
}

ApplyController::NixEvalHashResult
ApplyController::interpretNixEvalHashResult(int exitCode,
                                            int exitStatus,
                                            const QByteArray &stdoutBytes,
                                            const QByteArray &stderrBytes)
{
    NixEvalHashResult out;
    const QString stderrText = QString::fromUtf8(stderrBytes).trimmed();
    if (!stderrText.isEmpty())
        out.stderrWarning = stderrText;

    // QProcess::NormalExit == 0, CrashExit == 1
    if (exitStatus != 0) {
        out.error = QStringLiteral("nix eval aborted abnormally");
        if (!stderrText.isEmpty())
            out.error += QStringLiteral(": ") + stderrText.left(200);
        return out;
    }
    if (exitCode != 0) {
        out.error = QStringLiteral("Failed to evaluate ryokuSettingsHash");
        if (!stderrText.isEmpty())
            out.error += QStringLiteral(": ") + stderrText.left(200);
        return out;
    }

    out.hash = hashFromNixEvalStdout(stdoutBytes);
    if (out.hash.isEmpty()) {
        out.error = QStringLiteral("ryokuSettingsHash stdout empty");
        return out;
    }
    if (!isValidSha256Hex(out.hash)) {
        out.error = QStringLiteral("current hash has invalid format (len=%1)")
                        .arg(out.hash.size());
        return out;
    }

    out.ok = true;
    return out;
}

QString ApplyController::statusFromHashes(bool markerPresent,
                                          bool currentResolved,
                                          bool currentFailed,
                                          const QString &current,
                                          const QString &applied)
{
    if (currentFailed)
        return QString::fromLatin1(StatusHashError);
    if (!markerPresent || normalizeHash(applied).isEmpty())
        return QString::fromLatin1(StatusNeedsApply);
    if (!currentResolved || normalizeHash(current).isEmpty())
        return QString::fromLatin1(StatusIdle);
    if (!isValidSha256Hex(normalizeHash(current)) || !isValidSha256Hex(normalizeHash(applied)))
        return QString::fromLatin1(StatusHashError);
    if (hashesMatch(current, applied))
        return QString::fromLatin1(StatusApplied);
    return QString::fromLatin1(StatusNeedsApply);
}

QString ApplyController::needsApplyReason(bool markerPresent,
                                          bool currentResolved,
                                          bool currentFailed,
                                          const QString &current,
                                          const QString &applied)
{
    if (currentFailed)
        return QStringLiteral("current hash eval failed");
    if (!markerPresent)
        return QStringLiteral("applied marker absent");
    if (normalizeHash(applied).isEmpty())
        return QStringLiteral("applied hash empty");
    if (!currentResolved)
        return QStringLiteral("current hash not resolved yet");
    if (normalizeHash(current).isEmpty())
        return QStringLiteral("current hash empty");
    if (!isValidSha256Hex(normalizeHash(current)))
        return QStringLiteral("current hash invalid format");
    if (!isValidSha256Hex(normalizeHash(applied)))
        return QStringLiteral("applied hash invalid format");
    if (hashesMatch(current, applied))
        return QStringLiteral("hashes match (Applied)");
    return QStringLiteral("hashes differ");
}

QVector<ApplyController::PlanItem> ApplyController::knownInventory()
{
    return {
        {QStringLiteral("apps.flatpakDeclared"), QStringLiteral("Flatpak applications"), Scope::System},
        {QStringLiteral("appearance.loginWallpaper"), QStringLiteral("Login screen wallpaper"), Scope::System},
    };
}

QVariantList ApplyController::planToVariant(const QVector<PlanItem> &items, Scope scope)
{
    QVariantList out;
    for (const PlanItem &item : items) {
        if (item.scope != scope)
            continue;
        QVariantMap row;
        row.insert(QStringLiteral("id"), item.id);
        row.insert(QStringLiteral("label"), item.label);
        row.insert(QStringLiteral("scope"),
                   scope == Scope::User ? QStringLiteral("user") : QStringLiteral("system"));
        out.append(row);
    }
    return out;
}

QVector<ApplyController::PlanItem> ApplyController::buildPlanForNeedsApply(bool needsApply)
{
    if (!needsApply)
        return {};
    return knownInventory();
}

QString ApplyController::parseValidationResult(int exitCode, const QByteArray &combinedOutput)
{
    if (exitCode == 0)
        return QStringLiteral("flake check passed");
    const QString text = QString::fromUtf8(combinedOutput).trimmed();
    if (text.isEmpty())
        return QStringLiteral("flake check failed (exit %1)").arg(exitCode);
    const QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    if (!lines.isEmpty())
        return lines.last().trimmed();
    return QStringLiteral("flake check failed");
}

bool ApplyController::isAllowlistedNixEvalArgs(const QStringList &args)
{
    return args.size() == 3
           && args.at(0) == QLatin1String("eval")
           && args.at(1) == QLatin1String("--raw")
           && args.at(2) == QLatin1String(".#ryokuSettingsHash");
}

bool ApplyController::isAllowlistedFlakeCheckArgs(const QStringList &args)
{
    return args.size() == 2
           && args.at(0) == QLatin1String("flake")
           && args.at(1) == QLatin1String("check");
}

bool ApplyController::isAllowlistedHelperOperation(const QString &op)
{
    return op == QLatin1String("apply") || op == QLatin1String("rollback")
           || op == QLatin1String("switch-generation");
}

QStringList ApplyController::buildPkexecArgv(const QString &pkexec,
                                            const QString &helperAbsPath,
                                            const QString &operation)
{
    return buildPkexecArgv(pkexec, helperAbsPath, operation, -1);
}

QStringList ApplyController::buildPkexecArgv(const QString &pkexec,
                                            const QString &helperAbsPath,
                                            const QString &operation,
                                            int generation)
{
    if (!isAllowedPkexecPath(pkexec))
        return {};
    if (helperAbsPath.isEmpty() || !isAllowlistedHelperOperation(operation))
        return {};
    if (!helperAbsPath.startsWith(QLatin1Char('/')))
        return {};
    if (operation == QLatin1String("switch-generation")) {
        if (generation < 1)
            return {};
        return {helperAbsPath, operation, QString::number(generation)};
    }
    if (generation >= 0)
        return {}; // generation arg only valid for switch-generation
    return {helperAbsPath, operation};
}

QString ApplyController::systemPkexecPath()
{
    const QFileInfo nixos(QString::fromLatin1(SystemPkexecPath));
    if (nixos.exists() && nixos.isExecutable())
        return QString::fromLatin1(SystemPkexecPath);
    const QFileInfo debian(QString::fromLatin1(DebianPkexecPath));
    if (debian.exists() && debian.isExecutable())
        return QString::fromLatin1(DebianPkexecPath);
    return QString::fromLatin1(SystemPkexecPath);
}

bool ApplyController::isAllowedPkexecPath(const QString &path)
{
    return path == QLatin1String(SystemPkexecPath) || path == QLatin1String(DebianPkexecPath);
}

QString ApplyController::missingSystemPkexecMessage()
{
    return QStringLiteral("System pkexec wrapper is unavailable (/run/wrappers/bin/pkexec or /usr/bin/pkexec).");
}

bool ApplyController::parseStrictGenerationNumber(const QString &text, int *out)
{
    // Mirror ryoku_parse_generation_number: digits only, no leading zero, 1..1000000.
    static const QRegularExpression re(QStringLiteral("^[1-9][0-9]{0,6}$"));
    if (!re.match(text).hasMatch())
        return false;
    bool ok = false;
    const qlonglong v = text.toLongLong(&ok, 10);
    if (!ok || v < 1 || v > 1000000)
        return false;
    if (out)
        *out = static_cast<int>(v);
    return true;
}

QString ApplyController::systemGenerationLinkPath(int generation)
{
    if (generation < 1 || generation > 1000000)
        return {};
    // Debian Modular: Home Manager per-user generations (not NixOS system-*).
    const QString user = qEnvironmentVariable("USER");
    if (user.isEmpty())
        return {};
    return QStringLiteral("/nix/var/nix/profiles/per-user/%1/home-manager-%2-link")
        .arg(user)
        .arg(generation);
}

bool ApplyController::validateSystemGenerationExists(int generation, QString *canonicalOut,
                                                     QString *errorOut)
{
    if (canonicalOut)
        canonicalOut->clear();
    if (errorOut)
        errorOut->clear();
    if (generation < 1) {
        if (errorOut)
            *errorOut = QStringLiteral("generation must be >= 1");
        return false;
    }
    const QString linkpath = systemGenerationLinkPath(generation);
    if (linkpath.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("cannot resolve HM generation path (USER unset)");
        return false;
    }
    const QFileInfo linkFi(linkpath);
    if (!linkFi.exists()) {
        if (errorOut)
            *errorOut = QStringLiteral("generation link does not exist");
        return false;
    }
    if (!linkFi.isSymLink()) {
        if (errorOut)
            *errorOut = QStringLiteral("generation path is not a symlink");
        return false;
    }
    const QString resolved = linkFi.canonicalFilePath();
    if (resolved.isEmpty() || !resolved.startsWith(QStringLiteral("/nix/store/"))) {
        if (errorOut)
            *errorOut = QStringLiteral("generation target is not in /nix/store");
        return false;
    }
    // HM generations do not ship nixos-version / switch-to-configuration.
    if (canonicalOut)
        *canonicalOut = resolved;
    return true;
}

int ApplyController::readProfileGenerationNumber()
{
    const QString user = qEnvironmentVariable("USER");
    if (user.isEmpty())
        return -1;
    const QFileInfo fi(QStringLiteral("/nix/var/nix/profiles/per-user/%1/home-manager").arg(user));
    QString target = fi.symLinkTarget();
    if (target.isEmpty())
        return -1;
    // May be relative "home-manager-N-link" or absolute.
    const QFileInfo tfi(target);
    const QString name = tfi.fileName();
    static const QRegularExpression re(QStringLiteral("^home-manager-(\\d+)-link$"));
    const auto m = re.match(name);
    if (!m.hasMatch())
        return -1;
    bool ok = false;
    const int gen = m.captured(1).toInt(&ok);
    return ok ? gen : -1;
}

QString ApplyController::readProfileCanonicalPath()
{
    const QFileInfo fi(QStringLiteral("/nix/var/nix/profiles/system"));
    if (!fi.exists())
        return {};
    return fi.canonicalFilePath();
}

QString ApplyController::readCurrentSystemCanonicalPath()
{
    const QFileInfo fi(QStringLiteral("/run/current-system"));
    if (!fi.exists())
        return {};
    return fi.canonicalFilePath();
}

bool ApplyController::activeGenerationMatches(int generation)
{
    if (generation < 1)
        return false;
    if (readProfileGenerationNumber() != generation)
        return false;
    QString expected;
    if (!validateSystemGenerationExists(generation, &expected, nullptr))
        return false;
    const QString profile = readProfileCanonicalPath();
    const QString current = readCurrentSystemCanonicalPath();
    if (profile.isEmpty() || current.isEmpty())
        return false;
    return profile == expected && current == expected;
}

QString ApplyController::reconcileSwitchGenerationVerification(bool targetActive,
                                                               bool processLookedOk,
                                                               bool wasAuthorizationDenied,
                                                               bool wasFailedToStart,
                                                               const QString &classifiedStatus,
                                                               const QString &processDiagnostic,
                                                               QString *warningOut)
{
    if (warningOut)
        warningOut->clear();
    if (wasAuthorizationDenied
        || classifiedStatus == QLatin1String(StatusAuthorizationDenied))
        return QString::fromLatin1(StatusAuthorizationDenied);
    if (wasFailedToStart
        || classifiedStatus == QLatin1String(StatusAuthorizationError))
        return QString::fromLatin1(StatusAuthorizationError);
    if (targetActive) {
        if (!processLookedOk) {
            if (warningOut) {
                *warningOut = QStringLiteral(
                    "Generation is active, but the privileged process ended unexpectedly. "
                    "Diagnostic: %1")
                                  .arg(processDiagnostic.isEmpty() ? QStringLiteral("(none)")
                                                                   : processDiagnostic);
            }
        }
        // Success status is temporary; caller recomputes apply hash state next.
        return QString::fromLatin1(StatusNeedsApply);
    }
    Q_UNUSED(processLookedOk);
    // Target not active — never success, even if privileged exit was 0.
    return QString::fromLatin1(StatusSwitchFailed);
}

QString ApplyController::canonicalizeHelperPath(const QString &path)
{
    if (path.isEmpty() || !path.startsWith(QLatin1Char('/')))
        return {};
    const QFileInfo fi(path);
    if (!fi.exists() || !fi.isExecutable())
        return {};
    // Prefer canonical (resolves /nix/var/nix/profiles/... → /nix/store/...).
    // Polkit exec.path annotation uses the store path; symlink argv mismatches deny.
    const QString canonical = fi.canonicalFilePath();
    if (canonical.isEmpty() || !canonical.startsWith(QLatin1Char('/')))
        return {};
    if (!QFileInfo(canonical).isExecutable())
        return {};
    return canonical;
}

bool ApplyController::helperPathMatchesPolicyAnnotation(const QString &invokedPath,
                                                        const QString &policyExecPath)
{
    const QString a = canonicalizeHelperPath(invokedPath);
    const QString b = canonicalizeHelperPath(policyExecPath);
    if (a.isEmpty() || b.isEmpty())
        return false;
    return a == b;
}

ApplyController::PkexecClassification
ApplyController::classifyPkexecResult(int exitCode,
                                      int exitStatus,
                                      const QByteArray &stdoutBytes,
                                      const QByteArray &stderrBytes,
                                      bool wasRollback)
{
    return classifyPkexecResult(exitCode, exitStatus, -1, QString(), stdoutBytes, stderrBytes,
                                wasRollback);
}

ApplyController::PkexecClassification
ApplyController::classifyPkexecResult(int exitCode,
                                      int exitStatus,
                                      int processError,
                                      const QString &errorString,
                                      const QByteArray &stdoutBytes,
                                      const QByteArray &stderrBytes,
                                      bool wasRollback)
{
    PkexecClassification out;
    out.exitCode = exitCode;

    const QString stdoutText = QString::fromUtf8(stdoutBytes).trimmed();
    const QString stderrText = QString::fromUtf8(stderrBytes).trimmed();
    const QString combined = (stderrText + QLatin1Char('\n') + stdoutText).trimmed();
    const QString combinedLower = combined.toLower();
    const bool normalExit = (exitStatus == 0); // QProcess::NormalExit
    // QProcess::ProcessError: FailedToStart=0, Crashed=1, Timedout=2, ReadError=4, WriteError=3
    const bool failedToStart = (processError == 0);
    const bool crashedError = (processError == 1);
    const bool crashExit = (exitStatus == 1); // QProcess::CrashExit

    auto withEvidence = [&](const QString &status, const QString &headline, bool includeExitCode) {
        out.status = status;
        QString msg = headline;
        if (includeExitCode && normalExit)
            msg += QStringLiteral(" (pkexec NormalExit code=%1)").arg(exitCode);
        else if (!normalExit)
            msg += QStringLiteral(" (exitStatus=CrashExit; exitCode undefined/ignored=%1)")
                       .arg(exitCode);
        if (processError >= 0)
            msg += QStringLiteral(" [ProcessError=%1]").arg(processError);
        if (!errorString.isEmpty())
            msg += QStringLiteral("\n") + errorString.left(400);
        if (!stderrText.isEmpty())
            msg += QStringLiteral("\n") + stderrText.left(800);
        else if (!stdoutText.isEmpty())
            msg += QStringLiteral("\n") + stdoutText.left(800);
        out.message = msg;
        return out;
    };

    // --- Process lifecycle failures first (never trust exitCode here) ---
    if (failedToStart) {
        return withEvidence(QString::fromLatin1(StatusAuthorizationError),
                            QStringLiteral("Failed to start privileged apply (pkexec FailedToStart)"),
                            false);
    }
    if (crashExit || crashedError) {
        return withEvidence(
            QString::fromLatin1(wasRollback ? StatusRollbackFailed : StatusApplyFailed),
            QStringLiteral("Privileged apply process terminated unexpectedly"),
            false);
    }

    if (normalExit && exitCode == 0) {
        out.status = QString::fromLatin1(StatusApplied); // caller verifies hash
        out.message = QStringLiteral("pkexec NormalExit 0");
        return out;
    }

    // Only interpret exit codes on NormalExit.
    if (!normalExit) {
        return withEvidence(
            QString::fromLatin1(wasRollback ? StatusRollbackFailed : StatusApplyFailed),
            QStringLiteral("Privileged apply process terminated unexpectedly"),
            false);
    }

    // Infrastructure / exec failures — never call these AuthorizationDenied.
    if (combinedLower.contains(QLatin1String("no authentication agent"))
        || combinedLower.contains(QLatin1String("authentication agent not found"))
        || (combinedLower.contains(QLatin1String("cannot determine"))
            && combinedLower.contains(QLatin1String("agent")))) {
        return withEvidence(QString::fromLatin1(StatusAuthorizationError),
                            QStringLiteral(
                                "Polkit authentication agent is not running in this session "
                                "(DMS PolkitService / session agent)."),
                            true);
    }
    if (combinedLower.contains(QLatin1String("must be setuid"))
        || combinedLower.contains(QLatin1String("setuid root"))) {
        return withEvidence(QString::fromLatin1(StatusAuthorizationError),
                            QStringLiteral(
                                "pkexec must be setuid root — use /run/wrappers/bin/pkexec "
                                "(NixOS system wrapper), not pkgs.polkit from the store"),
                            true);
    }
    if (combinedLower.contains(QLatin1String("exec.path"))
        || combinedLower.contains(QLatin1String("not a valid absolute path"))
        || combinedLower.contains(QLatin1String("invalid use of"))) {
        return withEvidence(QString::fromLatin1(StatusAuthorizationError),
                            QStringLiteral(
                                "pkexec rejected helper path or polkit policy annotation mismatch"),
                            true);
    }
    if (combinedLower.contains(QLatin1String("org.freedesktop.policykit"))
        && (combinedLower.contains(QLatin1String("error"))
            || combinedLower.contains(QLatin1String("failed")))) {
        return withEvidence(QString::fromLatin1(StatusAuthorizationError),
                            QStringLiteral("Polkit/policy error launching privileged helper"),
                            true);
    }

    // Explicit user cancel / auth refused.
    const bool looksLikeUserDeny =
        combinedLower.contains(QLatin1String("not authorized"))
        || combinedLower.contains(QLatin1String("authorization requires authentication"))
        || combinedLower.contains(QLatin1String("user cancelled"))
        || combinedLower.contains(QLatin1String("user canceled"))
        || combinedLower.contains(QLatin1String("authentication dismissed"))
        || combinedLower.contains(QLatin1String("authentication failure"))
        || combinedLower.contains(QLatin1String("dismissed"));

    if (looksLikeUserDeny) {
        return withEvidence(QString::fromLatin1(StatusAuthorizationDenied),
                            QStringLiteral("Authorization denied"),
                            true);
    }

    if (exitCode == 126 || exitCode == 127) {
        if (combined.isEmpty()) {
            return withEvidence(
                QString::fromLatin1(StatusAuthorizationError),
                QStringLiteral(
                    "pkexec failed (NormalExit %1) with empty output — often a missing Polkit "
                    "authentication agent or helper/policy path mismatch")
                    .arg(exitCode),
                true);
        }
        return withEvidence(QString::fromLatin1(StatusAuthorizationError),
                            QStringLiteral("pkexec failed before privileged apply"),
                            true);
    }

    return withEvidence(QString::fromLatin1(wasRollback ? StatusRollbackFailed : StatusApplyFailed),
                        wasRollback ? QStringLiteral("Rollback failed")
                                    : QStringLiteral("Apply failed"),
                        true);
}

QString ApplyController::mapPrivilegedResult(int exitCode,
                                             bool hashMatchAfter,
                                             bool wasRollback,
                                             QString *statusOut)
{
    // Success-path helper (hash verification). Auth failures use classifyPkexecResult.
    if (exitCode != 0) {
        const auto cls = classifyPkexecResult(exitCode, 0, -1, QString(), {}, {}, wasRollback);
        if (statusOut)
            *statusOut = cls.status;
        return cls.message;
    }
    if (wasRollback) {
        if (statusOut)
            *statusOut = hashMatchAfter ? QString::fromLatin1(StatusApplied)
                                        : QString::fromLatin1(StatusNeedsApply);
        return QStringLiteral("Rollback finished");
    }
    if (hashMatchAfter) {
        if (statusOut)
            *statusOut = QString::fromLatin1(StatusApplied);
        return QStringLiteral("Applied — hash verified");
    }
    if (statusOut)
        *statusOut = QString::fromLatin1(StatusApplyFailed);
    return QStringLiteral("Apply exited 0 but applied hash does not match");
}

QString ApplyController::declarativePageStatusLabel(bool hasError,
                                                   bool unsavedDraft,
                                                   bool needsSystemApply,
                                                   const QString &applyStatus)
{
    if (hasError)
        return QCoreApplication::translate("ApplyController", "Error");
    if (unsavedDraft)
        return QCoreApplication::translate("ApplyController", "Unsaved changes");
    // Declarative saved vs generation — never a sticky page-local flag.
    if (needsSystemApply
        || applyStatus == QLatin1String(StatusNeedsApply)
        || applyStatus == QLatin1String(StatusReady)
        || applyStatus == QLatin1String(StatusValidationFailed)
        || applyStatus == QLatin1String(StatusAuthorizationDenied)
        || applyStatus == QLatin1String(StatusAuthorizationError)
        || applyStatus == QLatin1String(StatusApplyFailed)
        || applyStatus == QLatin1String(StatusRollbackFailed)
        || applyStatus == QLatin1String(StatusAwaitingAuthorization)
        || applyStatus == QLatin1String(StatusApplying)
        || applyStatus == QLatin1String(StatusValidating)
        || applyStatus == QLatin1String(StatusRollingBack)) {
        return QCoreApplication::translate("ApplyController", "Needs Apply");
    }
    if (applyStatus == QLatin1String(StatusApplied))
        return QCoreApplication::translate("ApplyController", "Applied");
    return QCoreApplication::translate("ApplyController", "Clean");
}

QString ApplyController::reconcilePrivilegedVerification(bool hashMatch,
                                                         bool processLookedOk,
                                                         bool wasRollback,
                                                         bool wasAuthorizationDenied,
                                                         bool wasFailedToStart,
                                                         const QString &processDiagnostic,
                                                         QString *warningOut)
{
    if (warningOut)
        warningOut->clear();

    if (hashMatch) {
        if (!processLookedOk) {
            if (warningOut) {
                *warningOut = QStringLiteral(
                    "System configuration was verified as applied, although the "
                    "privileged process ended unexpectedly.");
                if (!processDiagnostic.isEmpty())
                    *warningOut += QLatin1Char('\n') + processDiagnostic;
            }
        }
        return QString::fromLatin1(StatusApplied);
    }

    // No authoritative applied proof — keep process classification.
    if (wasAuthorizationDenied)
        return QString::fromLatin1(StatusAuthorizationDenied);
    if (wasFailedToStart)
        return QString::fromLatin1(StatusAuthorizationError);
    if (wasRollback)
        return QString::fromLatin1(StatusRollbackFailed);
    Q_UNUSED(processLookedOk);
    return QString::fromLatin1(StatusApplyFailed);
}

QString ApplyController::findNix() const
{
    const QString env = qEnvironmentVariable("RYOKU_NIX");
    if (!env.isEmpty() && QFile::exists(env))
        return env;
    return QStandardPaths::findExecutable(QStringLiteral("nix"));
}

QString ApplyController::findPkexec() const
{
    // Prefer NixOS setuid wrapper; accept Debian /usr/bin/pkexec. Never pkgs.polkit from PATH.
    for (const char *candidate : {SystemPkexecPath, DebianPkexecPath}) {
        const QString path = QString::fromLatin1(candidate);
        const QFileInfo fi(path);
        if (fi.exists() && fi.isExecutable())
            return path;
    }
    return {};
}

bool ApplyController::repoLooksValid() const
{
    return Ryoku::looksLikeRyokuRepo(m_repoPath);
}

void ApplyController::detectHelper()
{
    m_helperInstalled = false;
    m_helperPath.clear();

    auto tryPath = [](const QString &candidate) -> QString {
        // Debian policy annotates the STABLE /usr/local/libexec entrypoint.
        // Keep that exact path in pkexec argv, not the /nix/store symlink
        // target: executable/policy mismatch can fall back to generic Polkit.
        // For other backends (NixOS), preserve the canonical store path.
        static const QString stableDebian =
            QStringLiteral("/usr/local/libexec/ryoku-settings-apply");
        if (candidate == stableDebian) {
            const QFileInfo fi(candidate);
            return fi.exists() && fi.isExecutable() ? candidate : QString();
        }
        return canonicalizeHelperPath(candidate);
    };

    // Prefer published helper path files (system then user XDG), then stable
    // Debian libexec path, then PATH. Canonicalize so pkexec matches polkit exec.path.
    const QStringList pathFiles{
        helperPathFile(),
        QDir::home().filePath(QStringLiteral(".config/ryoku/settings-apply-helper")),
    };
    for (const QString &pf : pathFiles) {
        QFile f(pf);
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QString path = QString::fromUtf8(f.readAll()).trimmed();
        const QString canonical = tryPath(path);
        if (!canonical.isEmpty()) {
            m_helperPath = canonical;
            m_helperInstalled = true;
            return;
        }
    }

    const QStringList candidates{
        QStringLiteral("/usr/local/libexec/ryoku-settings-apply"),
        QStandardPaths::findExecutable(QStringLiteral("ryoku-settings-apply")),
    };
    for (const QString &found : candidates) {
        const QString canonical = tryPath(found);
        if (!canonical.isEmpty()) {
            m_helperPath = canonical;
            m_helperInstalled = true;
            return;
        }
    }
}

void ApplyController::captureCurrentSystem()
{
    const QFileInfo fi(QStringLiteral("/run/current-system"));
    if (fi.exists())
        m_previousGeneration = fi.canonicalFilePath();
    else
        m_previousGeneration.clear();
}

void ApplyController::watchMarker()
{
    if (!m_watcher) {
        m_watcher = new QFileSystemWatcher(this);
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &) {
            const QString path = appliedMarkerPath();
            if (QFileInfo::exists(path) && !m_watcher->files().contains(path))
                m_watcher->addPath(path);
            detectHelper();
            readAppliedMarker();
            recomputeApplyState();
            emit changed();
        });
        connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
            const QString path = appliedMarkerPath();
            if (QFileInfo::exists(path) && !m_watcher->files().contains(path))
                m_watcher->addPath(path);
            detectHelper();
            readAppliedMarker();
            recomputeApplyState();
            emit changed();
        });
    }

    const QString path = appliedMarkerPath();
    const QString dir = QFileInfo(path).absolutePath();
    if (QFileInfo::exists(dir) && !m_watcher->directories().contains(dir))
        m_watcher->addPath(dir);
    if (QFileInfo::exists(path) && !m_watcher->files().contains(path))
        m_watcher->addPath(path);
}

void ApplyController::readAppliedMarker()
{
    const QString path = appliedMarkerPath();
    QFile f(path);
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) {
        m_appliedMarkerPresent = false;
        m_appliedHash.clear();
        return;
    }

    const QString raw = normalizeHash(QString::fromUtf8(f.readAll()));
    // Bootstrap used to seed a non-hash sentinel ("unapplied"). Treat any
    // non-SHA256 marker as absent — not corruption — so Apply stays blocked
    // until a real generation writes a hash.
    if (!isValidSha256Hex(raw)) {
        m_appliedMarkerPresent = false;
        m_appliedHash.clear();
        if (!raw.isEmpty() && raw != QLatin1String("unapplied"))
            qInfo(lcApply) << "applied marker not a SHA-256 (treating as not-applied) len="
                           << raw.size();
        return;
    }

    m_appliedMarkerPresent = true;
    m_appliedHash = raw;
}

void ApplyController::refresh()
{
    m_nix = findNix();
    m_pkexec = findPkexec();
    detectHelper();
    m_currentHashResolved = false;
    m_currentHashFailed = false;
    m_currentHash.clear();
    readAppliedMarker();
    recomputeApplyState();
    emit changed();
    requestCurrentHash();
}

void ApplyController::requestCurrentHash()
{
    if (m_repoPath.isEmpty() || !repoLooksValid()) {
        m_currentHash.clear();
        m_currentHashResolved = true;
        m_currentHashFailed = true;
        m_lastError = QStringLiteral("Ryoku repository path invalid");
        recomputeApplyState();
        emit changed();
        return;
    }
    const QString flakeDir = Ryoku::resolveFlakeDir(m_repoPath);
    if (flakeDir.isEmpty()) {
        m_currentHash.clear();
        m_currentHashResolved = true;
        m_currentHashFailed = true;
        m_lastError = QStringLiteral(
            "Flake directory not found (expected flake.nix or distro/flake/flake.nix)");
        recomputeApplyState();
        emit changed();
        return;
    }
    if (m_nix.isEmpty()) {
        m_currentHash.clear();
        m_currentHashResolved = true;
        m_currentHashFailed = true;
        m_lastError = QStringLiteral("nix unavailable");
        recomputeApplyState();
        emit changed();
        return;
    }

    const QStringList args{QStringLiteral("eval"), QStringLiteral("--raw"),
                           QStringLiteral(".#ryokuSettingsHash")};
    if (!isAllowlistedNixEvalArgs(args)) {
        m_lastError = QStringLiteral("Internal: nix eval args not allowlisted");
        emit operationFailed(m_lastError);
        return;
    }

    if (!m_hashProcess) {
        m_hashProcess = new QProcess(this);
        connect(m_hashProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ApplyController::onCurrentHashFinished);
    }

    // Invalidate any in-flight eval before kill so waitForFinished does not
    // treat SIGKILL as a real HashError (stderr may still contain dirty-tree warnings).
    if (m_hashProcess->state() != QProcess::NotRunning) {
        m_hashProcess->setProperty("ryokuHashGen", -1);
        m_hashProcess->kill();
        m_hashProcess->waitForFinished(500);
    }

    ++m_hashGeneration;
    const int gen = m_hashGeneration;
    m_hashProcess->setProperty("ryokuHashGen", gen);

    m_currentHashResolved = false;
    m_currentHashFailed = false;
    m_progressStage = QStringLiteral("Reading current settings hash…");

    m_hashProcess->setProgram(m_nix);
    m_hashProcess->setArguments(args);
    m_hashProcess->setWorkingDirectory(flakeDir);
    m_hashProcess->setProcessChannelMode(QProcess::SeparateChannels);
    m_hashProcess->start();

    recomputeApplyState();
    emit changed();
}

void ApplyController::onCurrentHashFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_hashProcess)
        return;

    const int gen = m_hashProcess->property("ryokuHashGen").toInt();
    if (gen != m_hashGeneration)
        return;

    const QByteArray stdoutBytes = m_hashProcess->readAllStandardOutput();
    const QByteArray stderrBytes = m_hashProcess->readAllStandardError();

    const NixEvalHashResult result = interpretNixEvalHashResult(
        exitCode, static_cast<int>(status), stdoutBytes, stderrBytes);

    if (!result.stderrWarning.isEmpty()) {
        qWarning(lcApply) << "nix eval stderr (non-fatal if hash ok):" << result.stderrWarning.left(200);
        // Keep in Details log only when useful — do not fail on stderr alone.
        if (m_awaitingHashAfterPrivileged || !result.ok)
            appendLog(QStringLiteral("nix eval stderr:\n") + result.stderrWarning + QLatin1Char('\n'));
    }

    if (!result.ok) {
        m_currentHash.clear();
        m_currentHashResolved = true;
        m_currentHashFailed = true;
        m_lastError = result.error;
        qWarning(lcApply) << m_lastError;
    } else {
        m_currentHash = result.hash;
        m_currentHashResolved = true;
        m_currentHashFailed = false;
        if (m_status != QLatin1String(StatusValidating)
            && m_status != QLatin1String(StatusValidationFailed)
            && m_status != QLatin1String(StatusReady)
            && m_status != QLatin1String(StatusAwaitingAuthorization)
            && m_status != QLatin1String(StatusApplying)
            && m_status != QLatin1String(StatusRollingBack)
            && m_status != QLatin1String(StatusSwitchingGeneration)) {
            m_lastError.clear();
        }
    }

    m_progressStage.clear();

    if (m_awaitingHashAfterPrivileged) {
        m_awaitingHashAfterPrivileged = false;
        finishApplyVerification();
        return;
    }

    setBusy(false);
    recomputeApplyState();
    emit changed();
}

void ApplyController::recomputeApplyState()
{
    const bool inFlight = m_status == QLatin1String(StatusValidating)
                          || m_status == QLatin1String(StatusAwaitingAuthorization)
                          || m_status == QLatin1String(StatusApplying)
                          || m_status == QLatin1String(StatusRollingBack)
                          || m_status == QLatin1String(StatusSwitchingGeneration);

    const QString base = statusFromHashes(m_appliedMarkerPresent,
                                          m_currentHashResolved,
                                          m_currentHashFailed,
                                          m_currentHash,
                                          m_appliedHash);

    if (!inFlight && !m_busy) {
        if (m_lockfilePendingRebuild
            && (base == QLatin1String(StatusApplied)
                || base == QLatin1String(StatusNeedsApply))) {
            // Settings hash may still match — lock change alone requires rebuild.
            if (m_validatedOk)
                setStatus(QString::fromLatin1(StatusReady));
            else if (m_status != QLatin1String(StatusValidationFailed)
                     && m_status != QLatin1String(StatusAuthorizationDenied)
                     && m_status != QLatin1String(StatusAuthorizationError)
                     && m_status != QLatin1String(StatusApplyFailed)
                     && m_status != QLatin1String(StatusRollbackFailed)
                     && m_status != QLatin1String(StatusReady))
                setStatus(QString::fromLatin1(StatusNeedsApply));
        } else if (base == QLatin1String(StatusApplied)) {
            m_validatedOk = false;
            setStatus(QString::fromLatin1(StatusApplied));
            m_rollbackAvailable = true;
        } else if (m_validatedOk && base == QLatin1String(StatusNeedsApply)) {
            setStatus(QString::fromLatin1(StatusReady));
        } else if ((m_status == QLatin1String(StatusValidationFailed)
                    || m_status == QLatin1String(StatusAuthorizationDenied)
                    || m_status == QLatin1String(StatusAuthorizationError)
                    || m_status == QLatin1String(StatusApplyFailed)
                    || m_status == QLatin1String(StatusRollbackFailed))
                   && base == QLatin1String(StatusNeedsApply)) {
            // preserve terminal error until next successful transition
        } else if ((m_status == QLatin1String(StatusAuthorizationDenied)
                    || m_status == QLatin1String(StatusAuthorizationError))
                   && base == QLatin1String(StatusApplied)) {
            setStatus(QString::fromLatin1(StatusApplied));
        } else {
            setStatus(base);
        }
    }

    m_needsUserApply = false;
    if (m_lockfilePendingRebuild
        && (m_status == QLatin1String(StatusNeedsApply)
            || m_status == QLatin1String(StatusReady)
            || m_status == QLatin1String(StatusValidationFailed)
            || m_status == QLatin1String(StatusAuthorizationDenied)
            || m_status == QLatin1String(StatusAuthorizationError)
            || m_status == QLatin1String(StatusApplyFailed))) {
        m_needsSystemApply = true;
    } else if (m_status == QLatin1String(StatusApplied) || m_status == QLatin1String(StatusIdle)
               || m_status == QLatin1String(StatusHashError)) {
        m_needsSystemApply = false;
    } else if (m_status == QLatin1String(StatusReady)
               || m_status == QLatin1String(StatusValidationFailed)
               || m_status == QLatin1String(StatusNeedsApply)
               || m_status == QLatin1String(StatusAuthorizationDenied)
               || m_status == QLatin1String(StatusAuthorizationError)
               || m_status == QLatin1String(StatusApplyFailed)) {
        m_needsSystemApply = true;
    } else {
        m_needsSystemApply = false;
    }

    // Do not collapse to Applied on hash match while a lock rebuild is pending.
    if (m_validatedOk && hashesMatch(m_currentHash, m_appliedHash) && !inFlight
        && !m_lockfilePendingRebuild) {
        m_validatedOk = false;
        setStatus(QString::fromLatin1(StatusApplied));
        m_needsSystemApply = false;
        m_rollbackAvailable = true;
    }

    rebuildPlan();
}

void ApplyController::rebuildPlan()
{
    const bool pending = m_needsSystemApply || m_needsUserApply || m_lockfilePendingRebuild;
    QVector<PlanItem> items = buildPlanForNeedsApply(pending);
    if (m_lockfilePendingRebuild) {
        items.prepend({QStringLiteral("flake.lock"),
                       QStringLiteral("Flake lock (inputs)"),
                       Scope::System});
    }
    m_userPlan = planToVariant(items, Scope::User);
    m_systemPlan = planToVariant(items, Scope::System);
}

void ApplyController::setStatus(const QString &status)
{
    m_status = status;
}

void ApplyController::setBusy(bool busy)
{
    m_busy = busy;
}

void ApplyController::appendLog(const QString &chunk)
{
    m_applyLog += chunk;
    if (m_applyLog.size() > kMaxLogChars)
        m_applyLog = m_applyLog.right(kMaxLogChars);
    emit logChanged();
}

void ApplyController::clearLog()
{
    m_applyLog.clear();
    emit logChanged();
}

void ApplyController::validate()
{
    m_applyAfterValidate = false;
    if (!canValidate()) {
        emit operationFailed(QStringLiteral("Validate not available"));
        return;
    }
    if (m_nix.isEmpty()) {
        m_lastError = QStringLiteral("nix unavailable");
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    const QStringList args{QStringLiteral("flake"), QStringLiteral("check")};
    if (!isAllowlistedFlakeCheckArgs(args)) {
        m_lastError = QStringLiteral("Internal: flake check args not allowlisted");
        emit operationFailed(m_lastError);
        return;
    }

    if (m_validateProcess && m_validateProcess->state() != QProcess::NotRunning)
        return;

    if (!m_validateProcess) {
        m_validateProcess = new QProcess(this);
        connect(m_validateProcess, &QProcess::readyReadStandardOutput, this, [this]() {
            appendLog(QString::fromUtf8(m_validateProcess->readAllStandardOutput()));
        });
        connect(m_validateProcess, &QProcess::readyReadStandardError, this, [this]() {
            appendLog(QString::fromUtf8(m_validateProcess->readAllStandardError()));
        });
        connect(m_validateProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ApplyController::onValidateFinished);
    }

    const QString flakeDir = Ryoku::resolveFlakeDir(m_repoPath);
    if (flakeDir.isEmpty()) {
        m_lastError = QStringLiteral(
            "Flake directory not found (expected flake.nix or distro/flake/flake.nix)");
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    clearLog();
    appendLog(QStringLiteral("$ nix flake check  (cwd=%1)\n").arg(flakeDir));
    m_validatedOk = false;
    setBusy(true);
    setStatus(QString::fromLatin1(StatusValidating));
    m_progressStage = QStringLiteral("Validating configuration…");
    m_lastError.clear();
    m_lastValidationSummary.clear();
    emit changed();

    m_validateProcess->setProgram(m_nix);
    m_validateProcess->setArguments(args);
    m_validateProcess->setWorkingDirectory(flakeDir);
    m_validateProcess->setProcessChannelMode(QProcess::SeparateChannels);
    m_validateProcess->start();
}

void ApplyController::onValidateFinished(int exitCode, QProcess::ExitStatus status)
{
    Q_UNUSED(status);
    setBusy(false);
    m_progressStage.clear();

    if (m_validateProcess) {
        appendLog(QString::fromUtf8(m_validateProcess->readAllStandardOutput()));
        appendLog(QString::fromUtf8(m_validateProcess->readAllStandardError()));
    }

    m_lastValidationSummary = parseValidationResult(exitCode, m_applyLog.toUtf8());
    if (exitCode == 0) {
        m_validatedOk = true;
        m_lastError.clear();
        if (hashesMatch(m_currentHash, m_appliedHash) && m_appliedMarkerPresent
            && !m_lockfilePendingRebuild) {
            m_validatedOk = false;
            setStatus(QString::fromLatin1(StatusApplied));
            m_needsSystemApply = false;
            m_rollbackAvailable = true;
            m_applyAfterValidate = false;
            rebuildPlan();
            emit changed();
            return;
        }
        setStatus(QString::fromLatin1(StatusReady));
        m_needsSystemApply = true;
        rebuildPlan();
        emit changed();

        if (m_applyAfterValidate) {
            m_applyAfterValidate = false;
            launchPrivileged(PrivilegedOp::Apply);
        }
        return;
    }

    m_validatedOk = false;
    m_applyAfterValidate = false;
    m_lastError = m_lastValidationSummary;
    setStatus(QString::fromLatin1(StatusValidationFailed));
    m_needsSystemApply = true;
    rebuildPlan();
    emit operationFailed(m_lastError);
    emit changed();
}

void ApplyController::apply()
{
    if (m_unsavedDraft) {
        m_lastError = QStringLiteral("Save or reset pending changes before applying.");
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }
    if (!m_helperInstalled) {
        m_lastError = bootstrapHint();
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }
    if (!canApply() && !(m_validatedOk || m_status == QLatin1String(StatusReady))) {
        // Allow apply() to start validation first when NeedsApply.
        if (!(m_needsSystemApply && m_helperInstalled && !m_busy)) {
            m_lastError = QStringLiteral("Apply not available");
            emit operationFailed(m_lastError);
            emit changed();
            return;
        }
    }

    if (m_validatedOk || m_status == QLatin1String(StatusReady)) {
        launchPrivileged(PrivilegedOp::Apply);
        return;
    }

    // Validate first, then privileged apply.
    m_applyAfterValidate = true;
    validate();
}

void ApplyController::rollback()
{
    if (!canRollback()) {
        m_lastError = QStringLiteral("Rollback not available");
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }
    launchPrivileged(PrivilegedOp::Rollback);
}

QVariantMap ApplyController::generationSwitchPreview(int generation) const
{
    QVariantMap out;
    out.insert(QStringLiteral("generation"), generation);
    QString canon;
    QString err;
    const bool ok = validateSystemGenerationExists(generation, &canon, &err);
    out.insert(QStringLiteral("valid"), ok);
    out.insert(QStringLiteral("canonicalPath"), canon);
    out.insert(QStringLiteral("error"), err);
    out.insert(QStringLiteral("isCurrent"), readProfileGenerationNumber() == generation);
    out.insert(QStringLiteral("canSwitch"), canSwitchGeneration(generation));
    return out;
}

void ApplyController::switchGeneration(int generation)
{
    if (!canSwitchGeneration(generation)) {
        m_lastError = QStringLiteral("Cannot switch to generation %1").arg(generation);
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }
    launchPrivilegedSwitch(generation);
}

void ApplyController::launchPrivilegedSwitch(int generation)
{
    if (m_pkexec.isEmpty()) {
        m_lastError = missingSystemPkexecMessage();
        setStatus(QString::fromLatin1(StatusAuthorizationError));
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }
    if (!m_helperInstalled || m_helperPath.isEmpty()) {
        m_lastError = bootstrapHint();
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    const QStringList helperArgs =
        buildPkexecArgv(m_pkexec, m_helperPath, QStringLiteral("switch-generation"), generation);
    if (helperArgs.isEmpty()) {
        m_lastError = QStringLiteral("Internal: switch-generation argv not allowlisted");
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    if (privilegedInFlight()) {
        appendLog(QStringLiteral("\n[pkexec] ignored launch — privileged process already running\n"));
        return;
    }

    if (!m_privilegedProcess) {
        m_privilegedProcess = new QProcess(this);
        connect(m_privilegedProcess, &QProcess::readyReadStandardOutput, this, [this]() {
            appendLog(QString::fromUtf8(m_privilegedProcess->readAllStandardOutput()));
        });
        connect(m_privilegedProcess, &QProcess::readyReadStandardError, this, [this]() {
            appendLog(QString::fromUtf8(m_privilegedProcess->readAllStandardError()));
        });
        connect(m_privilegedProcess, &QProcess::errorOccurred, this,
                &ApplyController::onPrivilegedErrorOccurred);
        connect(m_privilegedProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ApplyController::onPrivilegedFinished);
    }

    m_pendingPrivileged = PrivilegedOp::SwitchGeneration;
    m_switchTargetGeneration = generation;
    m_privilegedLastProcessError = -1;
    m_privilegedErrorString.clear();
    m_privilegedClassifiedStatus.clear();
    ++m_privilegedGeneration;
    const int gen = m_privilegedGeneration;
    m_privilegedProcess->setProperty("ryokuPrivGen", gen);

    captureCurrentSystem();
    appendLog(QStringLiteral("\n$ %1 %2 switch-generation %3\n")
                  .arg(m_pkexec, m_helperPath)
                  .arg(generation));
    appendLog(QStringLiteral(
        "Note: repository files and flake.lock are not modified by generation switch.\n"));

    setBusy(true);
    setStatus(QString::fromLatin1(StatusAwaitingAuthorization));
    m_progressStage = QStringLiteral("Waiting for authorization…");
    m_lastError.clear();
    emit changed();

    connect(m_privilegedProcess, &QProcess::started, this, [this, gen]() {
        if (m_privilegedProcess
            && m_privilegedProcess->property("ryokuPrivGen").toInt() != gen)
            return;
        setStatus(QString::fromLatin1(StatusSwitchingGeneration));
        m_progressStage = QStringLiteral("Switching system generation…");
        emit changed();
    }, Qt::SingleShotConnection);

    m_privilegedProcess->setProgram(m_pkexec);
    m_privilegedProcess->setArguments(helperArgs);
    m_privilegedProcess->setProcessChannelMode(QProcess::SeparateChannels);
    m_privilegedProcess->start();
}

void ApplyController::launchPrivileged(PrivilegedOp op)
{
    if (op == PrivilegedOp::SwitchGeneration) {
        m_lastError = QStringLiteral("Internal: use launchPrivilegedSwitch");
        emit operationFailed(m_lastError);
        return;
    }
    if (m_pkexec.isEmpty()) {
        m_lastError = missingSystemPkexecMessage();
        setStatus(QString::fromLatin1(StatusAuthorizationError));
        m_needsSystemApply = true;
        rebuildPlan();
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }
    if (!m_helperInstalled || m_helperPath.isEmpty()) {
        m_lastError = bootstrapHint();
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    const QString opName = (op == PrivilegedOp::Rollback)
                               ? QStringLiteral("rollback")
                               : QStringLiteral("apply");
    const QStringList helperArgs = buildPkexecArgv(m_pkexec, m_helperPath, opName);
    if (helperArgs.isEmpty()) {
        m_lastError = QStringLiteral("Internal: privileged argv not allowlisted");
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    if (privilegedInFlight()) {
        appendLog(QStringLiteral("\n[pkexec] ignored launch — privileged process already running\n"));
        return;
    }

    if (!m_privilegedProcess) {
        m_privilegedProcess = new QProcess(this);
        connect(m_privilegedProcess, &QProcess::readyReadStandardOutput, this, [this]() {
            appendLog(QString::fromUtf8(m_privilegedProcess->readAllStandardOutput()));
        });
        connect(m_privilegedProcess, &QProcess::readyReadStandardError, this, [this]() {
            appendLog(QString::fromUtf8(m_privilegedProcess->readAllStandardError()));
        });
        connect(m_privilegedProcess, &QProcess::errorOccurred, this,
                &ApplyController::onPrivilegedErrorOccurred);
        connect(m_privilegedProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ApplyController::onPrivilegedFinished);
    }

    m_pendingPrivileged = op;
    m_privilegedLastProcessError = -1;
    m_privilegedErrorString.clear();
    ++m_privilegedGeneration;
    const int gen = m_privilegedGeneration;
    m_privilegedProcess->setProperty("ryokuPrivGen", gen);

    captureCurrentSystem();
    appendLog(QStringLiteral("\n$ %1 %2 %3\n")
                  .arg(m_pkexec, m_helperPath, opName));
    appendLog(QStringLiteral("[pkexec] program=%1 args=[%2] gen=%3\n")
                  .arg(m_pkexec, helperArgs.join(QLatin1Char(' ')))
                  .arg(gen));

    setBusy(true);
    setStatus(QString::fromLatin1(StatusAwaitingAuthorization));
    m_progressStage = QStringLiteral("Waiting for authorization…");
    m_lastError.clear();
    emit changed();

    connect(m_privilegedProcess, &QProcess::started, this, [this, op, gen]() {
        if (m_privilegedProcess
            && m_privilegedProcess->property("ryokuPrivGen").toInt() != gen)
            return;
        appendLog(QStringLiteral("[pkexec] started() pid=%1\n")
                      .arg(m_privilegedProcess ? m_privilegedProcess->processId() : -1));
        if (op == PrivilegedOp::Rollback) {
            setStatus(QString::fromLatin1(StatusRollingBack));
            m_progressStage = QStringLiteral("Rolling back system generation…");
        } else {
            setStatus(QString::fromLatin1(StatusApplying));
            m_progressStage = QStringLiteral("Applying system configuration…");
        }
        emit changed();
    }, Qt::SingleShotConnection);

    m_privilegedProcess->setProgram(m_pkexec);
    m_privilegedProcess->setArguments(helperArgs);
    m_privilegedProcess->setProcessChannelMode(QProcess::SeparateChannels);
    // Inherit session env (DBus/Wayland) so DMS PolkitService can prompt.
    m_privilegedProcess->start();
}

void ApplyController::onPrivilegedErrorOccurred(QProcess::ProcessError error)
{
    if (!m_privilegedProcess)
        return;
    m_privilegedLastProcessError = static_cast<int>(error);
    m_privilegedErrorString = m_privilegedProcess->errorString();
    appendLog(QStringLiteral("\n[pkexec] errorOccurred=%1 errorString=%2 program=%3\n")
                  .arg(static_cast<int>(error))
                  .arg(m_privilegedErrorString, m_privilegedProcess->program()));
    // finished() still follows for most errors — final classification happens there.
}

bool ApplyController::privilegedInFlight() const
{
    return m_privilegedProcess && m_privilegedProcess->state() != QProcess::NotRunning;
}

void ApplyController::onPrivilegedFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_privilegedProcess)
        return;

    const int gen = m_privilegedProcess->property("ryokuPrivGen").toInt();
    if (gen != m_privilegedGeneration)
        return;

    QByteArray stdoutBytes = m_privilegedProcess->readAllStandardOutput();
    QByteArray stderrBytes = m_privilegedProcess->readAllStandardError();
    appendLog(QString::fromUtf8(stdoutBytes));
    appendLog(QString::fromUtf8(stderrBytes));

    appendLog(QStringLiteral(
                  "\n[pkexec] finished exitCode=%1 exitStatus=%2 processError=%3 errorString=%4\n"
                  "[pkexec] program=%5 arguments=%6\n")
                  .arg(exitCode)
                  .arg(status == QProcess::CrashExit ? QStringLiteral("CrashExit")
                                                     : QStringLiteral("NormalExit"))
                  .arg(m_privilegedLastProcessError)
                  .arg(m_privilegedErrorString.isEmpty() ? QStringLiteral("(none)")
                                                         : m_privilegedErrorString)
                  .arg(m_privilegedProcess->program(),
                       m_privilegedProcess->arguments().join(QLatin1Char(' '))));

    const bool rb = m_pendingPrivileged == PrivilegedOp::Rollback;
    const bool sw = m_pendingPrivileged == PrivilegedOp::SwitchGeneration;
    const auto cls = classifyPkexecResult(exitCode,
                                          static_cast<int>(status),
                                          m_privilegedLastProcessError,
                                          m_privilegedErrorString,
                                          stdoutBytes,
                                          stderrBytes,
                                          rb);

    m_privilegedProcessDiagnostic = cls.message;
    m_privilegedClassifiedStatus = cls.status;
    m_privilegedWasFailedToStart = (m_privilegedLastProcessError == 0); // FailedToStart
    m_privilegedWasAuthDenied = (cls.status == QLatin1String(StatusAuthorizationDenied));
    m_privilegedProcessLookedOk =
        (status == QProcess::NormalExit && exitCode == 0 && !m_privilegedWasFailedToStart);

    if (!m_privilegedProcessLookedOk)
        appendLog(QStringLiteral("\n[pkexec] process diagnostic:\n") + cls.message + QLatin1Char('\n'));

    if (sw) {
        setBusy(true);
        setStatus(QString::fromLatin1(StatusSwitchingGeneration));
        m_progressStage = QStringLiteral("Verifying active generation…");
        emit changed();
        finishSwitchGenerationVerification();
        return;
    }

    // Marker/hash is authoritative — always verify after the process ends
    // (including CrashExit after a successful activation).
    setBusy(true);
    setStatus(m_privilegedProcessLookedOk
                  ? (rb ? QString::fromLatin1(StatusRollingBack)
                        : QString::fromLatin1(StatusApplying))
                  : QString::fromLatin1(StatusApplying));
    m_progressStage = QStringLiteral("Verifying applied generation…");
    captureCurrentSystem();
    detectHelper();
    readAppliedMarker();
    m_awaitingHashAfterPrivileged = true;
    emit changed();
    requestCurrentHash();
}

void ApplyController::finishSwitchGenerationVerification()
{
    const int target = m_switchTargetGeneration;
    const bool active = activeGenerationMatches(target);
    const int profileGen = readProfileGenerationNumber();
    const QString profilePath = readProfileCanonicalPath();
    const QString currentPath = readCurrentSystemCanonicalPath();

    appendLog(QStringLiteral("verify target=%1 active=%2 profileGen=%3\n"
                             "  profile=%4\n  current=%5\n")
                  .arg(target)
                  .arg(active ? QStringLiteral("yes") : QStringLiteral("no"))
                  .arg(profileGen)
                  .arg(profilePath.isEmpty() ? QStringLiteral("(missing)") : profilePath,
                       currentPath.isEmpty() ? QStringLiteral("(missing)") : currentPath));

    QString warning;
    const QString status = reconcileSwitchGenerationVerification(
        active,
        m_privilegedProcessLookedOk,
        m_privilegedWasAuthDenied,
        m_privilegedWasFailedToStart,
        m_privilegedClassifiedStatus,
        m_privilegedProcessDiagnostic,
        &warning);

    captureCurrentSystem();
    detectHelper();
    readAppliedMarker();

    if (status == QLatin1String(StatusSwitchFailed)
        || status == QLatin1String(StatusAuthorizationDenied)
        || status == QLatin1String(StatusAuthorizationError)) {
        setBusy(false);
        setStatus(status);
        m_progressStage.clear();
        m_needsSystemApply = true;
        m_lastError = m_privilegedProcessDiagnostic.isEmpty()
                          ? QStringLiteral("Generation switch failed — active generation is not %1")
                                .arg(target)
                          : m_privilegedProcessDiagnostic;
        if (!active && profileGen == target) {
            m_lastError += QStringLiteral(
                "\nProfile points to the target generation, but /run/current-system does not match. "
                "No automatic profile restoration was performed.");
        } else if (!active && profileGen > 0 && profileGen != target
                   && !m_privilegedProcessLookedOk) {
            m_lastError += QStringLiteral(
                "\nSystem profile still points to generation %1 — privileged activation did not "
                "move the profile to %2.")
                               .arg(profileGen)
                               .arg(target);
        }
        appendLog(QStringLiteral("\n✗ Generation switch verification failed\n"));
        rebuildPlan();
        emit operationFailed(m_lastError);
        emit changed();
        return;
    }

    // Target is active. Do NOT force Applied — recompute from settings hash/marker.
    // Lockfile pending state is intentionally left untouched (repo not modified).
    // Do not route through finishApplyVerification (that can clear lockfile pending).
    appendLog(QStringLiteral("\n✓ Active generation is %1\n").arg(target));
    if (!warning.isEmpty()) {
        m_lastError = warning;
        appendLog(QStringLiteral("⚠ ") + warning + QLatin1Char('\n'));
    } else {
        m_lastError.clear();
    }
    m_validatedOk = false;
    m_rollbackAvailable = true;
    m_awaitingHashAfterPrivileged = false;
    m_progressStage = QStringLiteral("Generation %1 active").arg(target);
    setStatus(QString::fromLatin1(StatusIdle)); // allow recomputeApplyState after hash
    setBusy(true);
    emit changed();
    requestCurrentHash();
}

void ApplyController::finishApplyVerification()
{
    m_progressStage.clear();
    setBusy(false);

    const bool match = hashesMatch(m_currentHash, m_appliedHash) && m_appliedMarkerPresent;
    const bool wasRollback = m_pendingPrivileged == PrivilegedOp::Rollback;

    QString warning;
    const QString status = reconcilePrivilegedVerification(match,
                                                           m_privilegedProcessLookedOk,
                                                           wasRollback,
                                                           m_privilegedWasAuthDenied,
                                                           m_privilegedWasFailedToStart,
                                                           m_privilegedProcessDiagnostic,
                                                           &warning);
    setStatus(status);

    if (status == QLatin1String(StatusApplied)) {
        m_validatedOk = false;
        m_needsSystemApply = false;
        m_lockfilePendingRebuild = false;
        m_rollbackAvailable = true;
        if (!warning.isEmpty()) {
            m_lastError = warning; // visible soft warning; state remains Applied
            appendLog(QStringLiteral("\n⚠ ") + warning + QLatin1Char('\n'));
            appendLog(QStringLiteral("✓ Hash verified — Applied (despite process anomaly)\n"));
        } else {
            m_lastError.clear();
            appendLog(QStringLiteral("\n✓ Hash verified — Applied\n"));
        }
        captureCurrentSystem();
        if (!m_previousGeneration.isEmpty())
            appendLog(QStringLiteral("current-system: ") + m_previousGeneration + QLatin1Char('\n'));
    } else if (wasRollback && m_privilegedProcessLookedOk && !match) {
        setStatus(QString::fromLatin1(StatusNeedsApply));
        m_needsSystemApply = true;
        m_rollbackAvailable = true;
        m_lastError.clear();
        appendLog(QStringLiteral("\nRollback complete — settings.json may need apply\n"));
    } else {
        m_needsSystemApply = true;
        m_lastError = m_privilegedProcessDiagnostic.isEmpty()
                          ? QStringLiteral("Apply failed — applied hash does not match")
                          : m_privilegedProcessDiagnostic;
        appendLog(QStringLiteral("\n✗ Privileged operation did not verify as applied\n"));
        emit operationFailed(m_lastError);
    }

    rebuildPlan();
    emit changed();
}
