#include "FlakeUpdateModel.h"

#include "ApplyController.h"
#include "RepoPath.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTimer>

Q_LOGGING_CATEGORY(lcFlakeUpdate, "ryoku.settings.flakeupdate")

namespace {
constexpr int kCheckTimeoutMs = 90000;
constexpr int kUpdateTimeoutMs = 300000;
} // namespace

FlakeUpdateModel::FlakeUpdateModel(QObject *parent)
    : QObject(parent)
{
    m_timeout = new QTimer(this);
    m_timeout->setSingleShot(true);
    connect(m_timeout, &QTimer::timeout, this, [this]() {
        if (m_op == Op::Check)
            onCheckTimeout();
        else if (m_op == Op::UpdateAll || m_op == Op::UpdateOne)
            onUpdateTimeout();
    });
}

FlakeUpdateModel::~FlakeUpdateModel()
{
    killActiveProcess();
}

void FlakeUpdateModel::setRepoPath(const QString &path)
{
    if (m_repoPath == path)
        return;
    m_repoPath = path;
    emit repoPathChanged();
}

void FlakeUpdateModel::setApplyController(ApplyController *ctrl)
{
    if (m_applyConn)
        disconnect(m_applyConn);
    m_apply = ctrl;
    if (m_apply) {
        m_applyConn = connect(m_apply, &ApplyController::changed, this,
                              &FlakeUpdateModel::onApplyControllerChanged);
    }
}

void FlakeUpdateModel::setRepoWasDirtyBeforeUpdate(bool dirty)
{
    if (m_repoWasDirtyBeforeUpdate == dirty)
        return;
    m_repoWasDirtyBeforeUpdate = dirty;
    emit changed();
}

QString FlakeUpdateModel::lockPath() const
{
    const QString flakeDir = Ryoku::resolveFlakeDir(m_repoPath);
    if (flakeDir.isEmpty())
        return {};
    return flakeDir + QStringLiteral("/flake.lock");
}

void FlakeUpdateModel::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
}

void FlakeUpdateModel::setPhase(const QString &phase)
{
    m_phase = phase;
}

void FlakeUpdateModel::appendDetails(const QString &chunk)
{
    m_details += chunk;
    if (m_details.size() > 12000)
        m_details = m_details.right(12000);
}

void FlakeUpdateModel::killActiveProcess()
{
    m_timeout->stop();
    if (!m_process)
        return;
    if (m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(1000);
    }
}

QString FlakeUpdateModel::statusLabel() const
{
    if (m_busy) {
        if (m_phase == QLatin1String("checking"))
            return tr("Checking for updates…");
        if (m_phase == QLatin1String("updating"))
            return tr("Updating flake.lock…");
        if (m_phase == QLatin1String("validating"))
            return tr("Validating…");
        return tr("Working…");
    }
    if (!m_error.isEmpty() && m_phase == QLatin1String("error"))
        return m_error;
    if (m_pendingLockChange)
        return tr("Lockfile changed — Apply recommended");
    if (m_checkRan) {
        if (m_updatesAvailable)
            return tr("Updates available");
        return tr("Up to date");
    }
    return tr("Update check not run");
}

QString FlakeUpdateModel::validationLabel() const
{
    if (m_validationLabel.isEmpty())
        return {};
    // Member always holds English source; translate at read time.
    return QCoreApplication::translate("FlakeUpdateModel", m_validationLabel.toUtf8().constData());
}

void FlakeUpdateModel::retranslateUi()
{
    for (int i = 0; i < m_inputs.size(); ++i) {
        QVariantMap m = m_inputs.at(i).toMap();
        const QString st = m.value(QStringLiteral("status")).toString();
        if (st == QLatin1String("up_to_date"))
            m.insert(QStringLiteral("statusLabel"), tr("Up to date"));
        else if (st == QLatin1String("update_available"))
            m.insert(QStringLiteral("statusLabel"), tr("Updates available"));
        else if (st == QLatin1String("check_failed"))
            m.insert(QStringLiteral("statusLabel"), tr("Check failed"));
        else if (st == QLatin1String("checking"))
            m.insert(QStringLiteral("statusLabel"), tr("Checking…"));
        else if (st == QLatin1String("unknown"))
            m.insert(QStringLiteral("statusLabel"), tr("Not checked"));
        m_inputs[i] = m;
    }
    const bool applied = m_apply && m_apply->status() == QLatin1String(ApplyController::StatusApplied);
    m_lockfileRebuildHint = rebuildHintFor(m_pendingLockChange, applied);
    emit changed();
}

bool FlakeUpdateModel::canValidatePending() const
{
    return m_pendingLockChange && !m_busy && m_apply;
}

QString FlakeUpdateModel::shortRev(const QString &rev)
{
    if (rev.isEmpty())
        return QStringLiteral("?");
    return rev.left(7);
}

QString FlakeUpdateModel::lockContentSha256(const QByteArray &bytes)
{
    return QString::fromLatin1(
        QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
}

QString FlakeUpdateModel::rebuildHintFor(bool pendingLockChange, bool settingsApplied)
{
    if (!pendingLockChange)
        return settingsApplied
                   ? QCoreApplication::translate("FlakeUpdateModel", "No lockfile update pending")
                   : QCoreApplication::translate("FlakeUpdateModel", "Settings may need apply");
    if (settingsApplied)
        return QCoreApplication::translate(
            "FlakeUpdateModel", "Flake lock changed since last rebuild — system rebuild required");
    return QCoreApplication::translate("FlakeUpdateModel", "Lockfile changed — Apply recommended");
}

QString FlakeUpdateModel::nixpkgsRunningHint(const QString &lockedNixpkgsRev,
                                             const QString &runningNixpkgsRev)
{
    if (lockedNixpkgsRev.isEmpty() || runningNixpkgsRev.isEmpty())
        return QStringLiteral("Running nixpkgs comparison unavailable "
                              "(generation has no full flake.lock fingerprint)");
    if (lockedNixpkgsRev == runningNixpkgsRev
        || lockedNixpkgsRev.startsWith(runningNixpkgsRev.left(7))
        || runningNixpkgsRev.startsWith(lockedNixpkgsRev.left(7)))
        return QStringLiteral("Running nixpkgs matches locked nixpkgs (partial signal)");
    return QStringLiteral("Running nixpkgs %1 ≠ locked %2 (partial — nixpkgs only)")
        .arg(shortRev(runningNixpkgsRev), shortRev(lockedNixpkgsRev));
}

QString FlakeUpdateModel::flakeUrlFromOriginal(const QVariantMap &original)
{
    const QString type = original.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("github") || type == QLatin1String("gitlab")) {
        const QString owner = original.value(QStringLiteral("owner")).toString();
        const QString repo = original.value(QStringLiteral("repo")).toString();
        if (owner.isEmpty() || repo.isEmpty())
            return {};
        const QString ref = original.value(QStringLiteral("ref")).toString();
        QString url = type + QLatin1Char(':') + owner + QLatin1Char('/') + repo;
        if (!ref.isEmpty())
            url += QLatin1Char('/') + ref;
        return url;
    }
    if (type == QLatin1String("indirect")) {
        const QString id = original.value(QStringLiteral("id")).toString();
        return id.isEmpty() ? QString() : id;
    }
    if (type == QLatin1String("path")) {
        const QString path = original.value(QStringLiteral("path")).toString();
        return path.isEmpty() ? QString() : (QStringLiteral("path:") + path);
    }
    if (type == QLatin1String("git") || type == QLatin1String("mercurial")) {
        const QString url = original.value(QStringLiteral("url")).toString();
        return url;
    }
    if (type == QLatin1String("tarball")) {
        return original.value(QStringLiteral("url")).toString();
    }
    return {};
}

QString FlakeUpdateModel::compareUpdateStatus(const QString &lockedRev, const QString &remoteRev)
{
    if (lockedRev.isEmpty() || remoteRev.isEmpty())
        return QStringLiteral("unknown");
    if (lockedRev == remoteRev)
        return QStringLiteral("up_to_date");
    return QStringLiteral("update_available");
}

bool FlakeUpdateModel::isValidInputName(const QString &name)
{
    static const QRegularExpression re(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._-]*$"));
    return re.match(name).hasMatch() && name.size() <= 64;
}

bool FlakeUpdateModel::isAllowlistedFlakeUpdateArgs(const QStringList &args,
                                                    const QStringList &knownInputs)
{
    if (args.size() < 2)
        return false;
    if (args.at(0) != QLatin1String("flake") || args.at(1) != QLatin1String("update"))
        return false;
    if (args.size() == 2)
        return true; // update all
    for (int i = 2; i < args.size(); ++i) {
        const QString &name = args.at(i);
        if (!isValidInputName(name))
            return false;
        if (!knownInputs.contains(name))
            return false;
    }
    return true;
}

QString FlakeUpdateModel::parseMetadataRevision(const QByteArray &json, QString *errorOut)
{
    if (errorOut)
        errorOut->clear();
    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut)
            *errorOut = pe.error != QJsonParseError::NoError ? pe.errorString()
                                                             : QStringLiteral("Expected JSON object");
        return {};
    }
    const QJsonObject obj = doc.object();
    QString rev = obj.value(QStringLiteral("revision")).toString();
    if (rev.isEmpty()) {
        const QJsonObject locked = obj.value(QStringLiteral("locked")).toObject();
        rev = locked.value(QStringLiteral("rev")).toString();
    }
    if (rev.isEmpty() && errorOut)
        *errorOut = QStringLiteral("No revision in metadata");
    return rev;
}

QString FlakeUpdateModel::classifyProcessFailure(int exitCode, QProcess::ExitStatus status,
                                                 QProcess::ProcessError processError,
                                                 const QByteArray &stderrBytes)
{
    const QString err = QString::fromUtf8(stderrBytes).trimmed();
    if (processError == QProcess::FailedToStart)
        return QStringLiteral("Failed to start nix (is it on PATH?)");
    if (processError == QProcess::Timedout || status == QProcess::CrashExit)
        return err.isEmpty() ? QStringLiteral("nix process timed out or crashed") : err.left(240);
    if (err.contains(QStringLiteral("Unable to download"), Qt::CaseInsensitive)
        || err.contains(QStringLiteral("Network is unreachable"), Qt::CaseInsensitive)
        || err.contains(QStringLiteral("Could not resolve host"), Qt::CaseInsensitive)
        || err.contains(QStringLiteral("SSL"), Qt::CaseInsensitive)
        || err.contains(QStringLiteral("curl"), Qt::CaseInsensitive))
        return QStringLiteral("Network error while contacting flake input");
    if (!err.isEmpty())
        return err.split(QLatin1Char('\n')).last().trimmed().left(240);
    return QStringLiteral("nix failed (exit %1)").arg(exitCode);
}

QVariantList FlakeUpdateModel::parseLockRootInputs(const QByteArray &lockJson, QString *errorOut)
{
    if (errorOut)
        errorOut->clear();
    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(lockJson, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut)
            *errorOut = pe.error != QJsonParseError::NoError ? pe.errorString()
                                                             : QStringLiteral("Expected JSON object");
        return {};
    }
    const QJsonObject root = doc.object();
    const QJsonObject nodes = root.value(QStringLiteral("nodes")).toObject();
    const QJsonObject rootNode = nodes.value(QStringLiteral("root")).toObject();
    const QJsonObject inputsMap = rootNode.value(QStringLiteral("inputs")).toObject();

    QStringList names = inputsMap.keys();
    names.sort(Qt::CaseInsensitive);
    QVariantList out;
    for (const QString &name : names) {
        QVariantMap row;
        row.insert(QStringLiteral("name"), name);
        const QString nodeKey = inputsMap.value(name).toString();
        row.insert(QStringLiteral("nodeKey"), nodeKey);
        QString lockedRev;
        QString originalUrl;
        QString summary;
        if (!nodeKey.isEmpty() && nodes.contains(nodeKey)) {
            const QJsonObject node = nodes.value(nodeKey).toObject();
            const QJsonObject locked = node.value(QStringLiteral("locked")).toObject();
            lockedRev = locked.value(QStringLiteral("rev")).toString();
            const QVariantMap original = node.value(QStringLiteral("original")).toObject().toVariantMap();
            originalUrl = flakeUrlFromOriginal(original);
            const QString owner = locked.value(QStringLiteral("owner")).toString();
            const QString repo = locked.value(QStringLiteral("repo")).toString();
            if (!owner.isEmpty() && !repo.isEmpty())
                summary = QStringLiteral("%1/%2@%3").arg(owner, repo, shortRev(lockedRev));
            else
                summary = shortRev(lockedRev);
        }
        row.insert(QStringLiteral("lockedRev"), lockedRev);
        row.insert(QStringLiteral("remoteRev"), QString());
        row.insert(QStringLiteral("originalUrl"), originalUrl);
        row.insert(QStringLiteral("summary"), summary);
        row.insert(QStringLiteral("status"), QStringLiteral("unknown"));
        row.insert(QStringLiteral("statusLabel"), tr("Not checked"));
        out.append(row);
    }
    return out;
}

QVariantList FlakeUpdateModel::diffLockedRevisions(const QByteArray &oldLock,
                                                   const QByteArray &newLock)
{
    QString err;
    const QVariantList oldInputs = parseLockRootInputs(oldLock, &err);
    const QVariantList newInputs = parseLockRootInputs(newLock, &err);
    QHash<QString, QString> oldRevs;
    for (const QVariant &v : oldInputs) {
        const QVariantMap m = v.toMap();
        oldRevs.insert(m.value(QStringLiteral("name")).toString(),
                       m.value(QStringLiteral("lockedRev")).toString());
    }
    QVariantList diff;
    for (const QVariant &v : newInputs) {
        const QVariantMap m = v.toMap();
        const QString name = m.value(QStringLiteral("name")).toString();
        const QString neu = m.value(QStringLiteral("lockedRev")).toString();
        const QString old = oldRevs.value(name);
        if (old == neu)
            continue;
        QVariantMap row;
        row.insert(QStringLiteral("name"), name);
        row.insert(QStringLiteral("oldRev"), old);
        row.insert(QStringLiteral("newRev"), neu);
        row.insert(QStringLiteral("label"),
                   QStringLiteral("%1 → %2").arg(shortRev(old), shortRev(neu)));
        diff.append(row);
    }
    return diff;
}

bool FlakeUpdateModel::writeAtomicFile(const QString &path, const QByteArray &bytes,
                                       QString *errorOut)
{
    if (errorOut)
        errorOut->clear();
    QSaveFile sf(path);
    if (!sf.open(QIODevice::WriteOnly)) {
        if (errorOut)
            *errorOut = sf.errorString();
        return false;
    }
    if (sf.write(bytes) != bytes.size()) {
        if (errorOut)
            *errorOut = QStringLiteral("Short write");
        sf.cancelWriting();
        return false;
    }
    if (!sf.commit()) {
        if (errorOut)
            *errorOut = sf.errorString();
        return false;
    }
    return true;
}

QStringList FlakeUpdateModel::knownInputNames() const
{
    QStringList names;
    for (const QVariant &v : m_inputs)
        names.append(v.toMap().value(QStringLiteral("name")).toString());
    return names;
}

void FlakeUpdateModel::loadInputsFromLock()
{
    QFile f(lockPath());
    if (!f.open(QIODevice::ReadOnly)) {
        m_inputs.clear();
        return;
    }
    QString err;
    m_inputs = parseLockRootInputs(f.readAll(), &err);
    if (!err.isEmpty())
        qWarning(lcFlakeUpdate) << "lock parse" << err;
}

void FlakeUpdateModel::refresh()
{
    if (m_busy)
        return;
    m_error.clear();
    loadInputsFromLock();
    refreshRunningNixpkgsHint();
    m_lockfileRebuildHint = rebuildHintFor(
        m_pendingLockChange,
        m_apply && m_apply->status() == QLatin1String(ApplyController::StatusApplied));
    emit changed();
}

void FlakeUpdateModel::refreshRunningNixpkgsHint()
{
    QString lockedNixpkgs;
    for (const QVariant &v : m_inputs) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("name")).toString() == QLatin1String("nixpkgs")) {
            lockedNixpkgs = m.value(QStringLiteral("lockedRev")).toString();
            break;
        }
    }
    // Best-effort partial signal — generation has no full flake.lock fingerprint.
    QProcess proc;
    proc.setProgram(QStringLiteral("nixos-version"));
    proc.setArguments({QStringLiteral("--json")});
    proc.setProcessChannelMode(QProcess::SeparateChannels);
    proc.start();
    QString running;
    if (proc.waitForFinished(3000) && proc.exitStatus() == QProcess::NormalExit
        && proc.exitCode() == 0) {
        const QJsonDocument doc = QJsonDocument::fromJson(proc.readAllStandardOutput());
        if (doc.isObject())
            running = doc.object().value(QStringLiteral("nixpkgsRevision")).toString();
    }
    m_runningNixpkgsHint = nixpkgsRunningHint(lockedNixpkgs, running);
}

void FlakeUpdateModel::syncApplyBridge()
{
    if (!m_apply)
        return;
    m_apply->setLockfilePendingRebuild(m_pendingLockChange);
}

bool FlakeUpdateModel::snapshotLockBeforeMutation(QString *errorOut)
{
    QFile f(lockPath());
    if (!f.open(QIODevice::ReadOnly)) {
        if (errorOut)
            *errorOut = QStringLiteral("Cannot read flake.lock");
        return false;
    }
    m_lockSnapshot = f.readAll();
    m_lockSnapshotHash = lockContentSha256(m_lockSnapshot);
    return true;
}

void FlakeUpdateModel::checkForUpdates()
{
    if (m_busy || m_repoPath.isEmpty())
        return;
    loadInputsFromLock();
    m_checkQueue.clear();
    for (const QVariant &v : m_inputs) {
        const QVariantMap m = v.toMap();
        if (!m.value(QStringLiteral("originalUrl")).toString().isEmpty())
            m_checkQueue.append(m.value(QStringLiteral("name")).toString());
    }
    if (m_checkQueue.isEmpty()) {
        m_error = QStringLiteral("No flake inputs with resolvable original URLs");
        m_checkRan = true;
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }

    // Reset per-input status
    for (int i = 0; i < m_inputs.size(); ++i) {
        QVariantMap m = m_inputs[i].toMap();
        m.insert(QStringLiteral("status"), QStringLiteral("checking"));
        m.insert(QStringLiteral("statusLabel"), tr("Checking…"));
        m.insert(QStringLiteral("remoteRev"), QString());
        m_inputs[i] = m;
    }

    m_details.clear();
    m_error.clear();
    m_checkRan = false;
    m_updatesAvailable = false;
    m_checkIndex = 0;
    m_op = Op::Check;
    setBusy(true);
    setPhase(QStringLiteral("checking"));
    emit changed();
    startNextCheck();
}

void FlakeUpdateModel::startNextCheck()
{
    if (m_checkIndex >= m_checkQueue.size()) {
        m_timeout->stop();
        m_op = Op::None;
        setBusy(false);
        setPhase(QStringLiteral("idle"));
        m_checkRan = true;
        m_updatesAvailable = false;
        for (const QVariant &v : m_inputs) {
            if (v.toMap().value(QStringLiteral("status")).toString()
                == QLatin1String("update_available")) {
                m_updatesAvailable = true;
                break;
            }
        }
        emit changed();
        return;
    }

    const QString name = m_checkQueue.at(m_checkIndex);
    QString url;
    for (const QVariant &v : m_inputs) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("name")).toString() == name) {
            url = m.value(QStringLiteral("originalUrl")).toString();
            break;
        }
    }
    if (url.isEmpty()) {
        ++m_checkIndex;
        startNextCheck();
        return;
    }

    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                [this](int code, QProcess::ExitStatus st) {
                    if (m_op == Op::Check)
                        onCheckProcessFinished(code, st);
                    else if (m_op == Op::UpdateAll || m_op == Op::UpdateOne)
                        onUpdateProcessFinished(code, st);
                });
    }
    if (m_process->state() != QProcess::NotRunning)
        return;

    const QString flakeDir = Ryoku::resolveFlakeDir(m_repoPath);
    if (flakeDir.isEmpty()) {
        appendDetails(QStringLiteral("flake directory unavailable\n"));
        m_error = QStringLiteral(
            "Flake directory not found (expected flake.nix or distro/flake/flake.nix)");
        setBusy(false);
        setPhase(QStringLiteral("error"));
        m_op = Op::None;
        emit changed();
        return;
    }
    appendDetails(QStringLiteral("$ nix flake metadata --json %1  (cwd=%2)\n").arg(url, flakeDir));
    m_process->setProgram(m_nix);
    m_process->setArguments(
        {QStringLiteral("flake"), QStringLiteral("metadata"), QStringLiteral("--json"), url});
    m_process->setWorkingDirectory(flakeDir);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_timeout->start(kCheckTimeoutMs);
    m_process->start();
}

void FlakeUpdateModel::onCheckTimeout()
{
    if (m_op != Op::Check || !m_process)
        return;
    appendDetails(QStringLiteral("timeout\n"));
    m_process->kill();
}

void FlakeUpdateModel::onCheckProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    m_timeout->stop();
    if (!m_process || m_checkIndex >= m_checkQueue.size())
        return;

    const QString name = m_checkQueue.at(m_checkIndex);
    const QByteArray out = m_process->readAllStandardOutput();
    const QByteArray err = m_process->readAllStandardError();
    if (!err.isEmpty())
        appendDetails(QString::fromUtf8(err));

    QString lockedRev;
    for (int i = 0; i < m_inputs.size(); ++i) {
        QVariantMap m = m_inputs[i].toMap();
        if (m.value(QStringLiteral("name")).toString() != name)
            continue;
        lockedRev = m.value(QStringLiteral("lockedRev")).toString();
        if (status != QProcess::NormalExit || exitCode != 0) {
            const QString msg = classifyProcessFailure(
                exitCode, status, m_process->error(), err);
            m.insert(QStringLiteral("status"), QStringLiteral("check_failed"));
            m.insert(QStringLiteral("statusLabel"), tr("Check failed"));
            m.insert(QStringLiteral("error"), msg);
            m_inputs[i] = m;
            break;
        }
        QString parseErr;
        const QString remote = parseMetadataRevision(out, &parseErr);
        if (remote.isEmpty()) {
            m.insert(QStringLiteral("status"), QStringLiteral("check_failed"));
            m.insert(QStringLiteral("statusLabel"), tr("Check failed"));
            m.insert(QStringLiteral("error"), parseErr);
            m_inputs[i] = m;
            break;
        }
        const QString st = compareUpdateStatus(lockedRev, remote);
        m.insert(QStringLiteral("remoteRev"), remote);
        m.insert(QStringLiteral("status"), st);
        m.insert(QStringLiteral("statusLabel"),
                 st == QLatin1String("up_to_date")
                     ? tr("Up to date")
                     : tr("Updates available"));
        m.insert(QStringLiteral("summary"),
                 QStringLiteral("%1 → %2")
                     .arg(shortRev(lockedRev), shortRev(remote)));
        m_inputs[i] = m;
        break;
    }

    ++m_checkIndex;
    emit changed();
    startNextCheck();
}

void FlakeUpdateModel::updateAll()
{
    if (m_busy || m_repoPath.isEmpty())
        return;
    // Debian Modular: never mutate flake.lock by default (preserve guest lock).
    if (qEnvironmentVariable(QByteArrayLiteral("RYOKU_ALLOW_FLAKE_UPDATE")) != QLatin1String("1")) {
        m_error = QStringLiteral(
            "nix flake update is disabled by default (set RYOKU_ALLOW_FLAKE_UPDATE=1 to opt in)");
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    const QString flakeDir = Ryoku::resolveFlakeDir(m_repoPath);
    if (flakeDir.isEmpty()) {
        m_error = QStringLiteral(
            "Flake directory not found (expected flake.nix or distro/flake/flake.nix)");
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    loadInputsFromLock();
    QString err;
    if (!snapshotLockBeforeMutation(&err)) {
        m_error = err;
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    m_updateTargetInput.clear();
    m_details.clear();
    m_error.clear();
    m_validationLabel = QStringLiteral("Update pending validation");
    m_lockDiff.clear();
    m_op = Op::UpdateAll;
    setBusy(true);
    setPhase(QStringLiteral("updating"));
    emit changed();

    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                [this](int code, QProcess::ExitStatus st) {
                    if (m_op == Op::Check)
                        onCheckProcessFinished(code, st);
                    else if (m_op == Op::UpdateAll || m_op == Op::UpdateOne)
                        onUpdateProcessFinished(code, st);
                });
    }
    const QStringList args{QStringLiteral("flake"), QStringLiteral("update")};
    if (!isAllowlistedFlakeUpdateArgs(args, knownInputNames())) {
        m_error = QStringLiteral("Internal: update args not allowlisted");
        setBusy(false);
        setPhase(QStringLiteral("error"));
        m_op = Op::None;
        emit changed();
        return;
    }
    appendDetails(QStringLiteral("$ nix flake update  (cwd=%1)\n").arg(flakeDir));
    m_process->setProgram(m_nix);
    m_process->setArguments(args);
    m_process->setWorkingDirectory(flakeDir);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_timeout->start(kUpdateTimeoutMs);
    m_process->start();
}

void FlakeUpdateModel::updateInput(const QString &inputName)
{
    if (m_busy || m_repoPath.isEmpty())
        return;
    if (qEnvironmentVariable(QByteArrayLiteral("RYOKU_ALLOW_FLAKE_UPDATE")) != QLatin1String("1")) {
        m_error = QStringLiteral(
            "nix flake update is disabled by default (set RYOKU_ALLOW_FLAKE_UPDATE=1 to opt in)");
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    const QString flakeDir = Ryoku::resolveFlakeDir(m_repoPath);
    if (flakeDir.isEmpty()) {
        m_error = QStringLiteral(
            "Flake directory not found (expected flake.nix or distro/flake/flake.nix)");
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    loadInputsFromLock();
    if (!isValidInputName(inputName) || !knownInputNames().contains(inputName)) {
        m_error = QStringLiteral("Unknown or invalid input name");
        emit changed();
        return;
    }
    QString err;
    if (!snapshotLockBeforeMutation(&err)) {
        m_error = err;
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    m_updateTargetInput = inputName;
    m_details.clear();
    m_error.clear();
    m_validationLabel = QStringLiteral("Update pending validation");
    m_lockDiff.clear();
    m_op = Op::UpdateOne;
    setBusy(true);
    setPhase(QStringLiteral("updating"));
    emit changed();

    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
                [this](int code, QProcess::ExitStatus st) {
                    if (m_op == Op::Check)
                        onCheckProcessFinished(code, st);
                    else if (m_op == Op::UpdateAll || m_op == Op::UpdateOne)
                        onUpdateProcessFinished(code, st);
                });
    }
    const QStringList args{QStringLiteral("flake"), QStringLiteral("update"), inputName};
    if (!isAllowlistedFlakeUpdateArgs(args, knownInputNames())) {
        m_error = QStringLiteral("Internal: update args not allowlisted");
        setBusy(false);
        setPhase(QStringLiteral("error"));
        m_op = Op::None;
        emit changed();
        return;
    }
    appendDetails(QStringLiteral("$ nix flake update %1  (cwd=%2)\n").arg(inputName, flakeDir));
    m_process->setProgram(m_nix);
    m_process->setArguments(args);
    m_process->setWorkingDirectory(flakeDir);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_timeout->start(kUpdateTimeoutMs);
    m_process->start();
}

void FlakeUpdateModel::onUpdateTimeout()
{
    if ((m_op != Op::UpdateAll && m_op != Op::UpdateOne) || !m_process)
        return;
    appendDetails(QStringLiteral("timeout\n"));
    m_process->kill();
}

void FlakeUpdateModel::onUpdateProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    finishUpdateFromProcess(exitCode, status);
}

void FlakeUpdateModel::finishUpdateFromProcess(int exitCode, QProcess::ExitStatus status)
{
    m_timeout->stop();
    setBusy(false);
    m_op = Op::None;
    if (!m_process)
        return;

    const QByteArray out = m_process->readAllStandardOutput();
    const QByteArray err = m_process->readAllStandardError();
    if (!out.isEmpty())
        appendDetails(QString::fromUtf8(out));
    if (!err.isEmpty())
        appendDetails(QString::fromUtf8(err));

    if (status != QProcess::NormalExit || exitCode != 0) {
        m_error = classifyProcessFailure(exitCode, status, m_process->error(), err);
        setPhase(QStringLiteral("error"));
        m_canRevert = !m_lockSnapshot.isEmpty();
        // Restore snapshot on failed update if lock was partially written
        QFile cur(lockPath());
        if (cur.open(QIODevice::ReadOnly)) {
            const QByteArray now = cur.readAll();
            cur.close();
            if (lockContentSha256(now) != m_lockSnapshotHash && !m_lockSnapshot.isEmpty()) {
                QString werr;
                writeAtomicFile(lockPath(), m_lockSnapshot, &werr);
            }
        }
        emit changed();
        return;
    }

    QFile cur(lockPath());
    if (!cur.open(QIODevice::ReadOnly)) {
        m_error = QStringLiteral("Cannot read flake.lock after update");
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    const QByteArray neu = cur.readAll();
    const QString neuHash = lockContentSha256(neu);
    m_lockDiff = diffLockedRevisions(m_lockSnapshot, neu);

    if (neuHash == m_lockSnapshotHash) {
        m_pendingLockChange = false;
        m_canRevert = false;
        m_validationLabel = QStringLiteral("Lockfile unchanged");
        m_error.clear();
        setPhase(QStringLiteral("idle"));
        loadInputsFromLock();
        syncApplyBridge();
        emit changed();
        return;
    }

    m_pendingLockChange = true;
    m_canRevert = true;
    m_validationLabel = QStringLiteral("Update pending validation");
    m_lockfileRebuildHint = rebuildHintFor(true, m_apply && m_apply->status() == QLatin1String(ApplyController::StatusApplied));
    setPhase(QStringLiteral("idle"));
    loadInputsFromLock();
    refreshRunningNixpkgsHint();
    syncApplyBridge();
    emit lockfileChanged();
    emit changed();
    // Intentionally do NOT call apply / nixos-rebuild.
}

void FlakeUpdateModel::revertUpdate()
{
    if (m_busy || !m_canRevert || m_lockSnapshot.isEmpty())
        return;
    QString err;
    if (!writeAtomicFile(lockPath(), m_lockSnapshot, &err)) {
        m_error = err.isEmpty() ? QStringLiteral("Revert failed") : err;
        setPhase(QStringLiteral("error"));
        emit changed();
        return;
    }
    m_pendingLockChange = false;
    m_canRevert = false;
    m_lockDiff.clear();
    m_validationLabel = QStringLiteral("Update reverted");
    m_error.clear();
    m_lockfileRebuildHint = rebuildHintFor(false, true);
    loadInputsFromLock();
    syncApplyBridge();
    emit lockfileChanged();
    emit changed();
}

void FlakeUpdateModel::validatePending()
{
    if (!canValidatePending())
        return;
    m_validationLabel = QStringLiteral("Validating…");
    setPhase(QStringLiteral("validating"));
    emit changed();
    m_apply->validate();
}

void FlakeUpdateModel::onApplyControllerChanged()
{
    if (!m_apply)
        return;

    // Successful privileged apply clears lock pending on ApplyController.
    if (m_pendingLockChange && !m_apply->lockfilePendingRebuild()
        && m_apply->status() == QLatin1String(ApplyController::StatusApplied)) {
        m_pendingLockChange = false;
        m_canRevert = false;
        m_lockSnapshot.clear();
        m_lockSnapshotHash.clear();
        m_lockDiff.clear();
        m_validationLabel = QStringLiteral("Applied via system rebuild");
        m_lockfileRebuildHint = rebuildHintFor(false, true);
        setPhase(QStringLiteral("idle"));
        emit changed();
        return;
    }

    if (m_phase != QLatin1String("validating") || m_apply->busy())
        return;

    const QString st = m_apply->status();
    if (st == QLatin1String(ApplyController::StatusReady)
        || (st == QLatin1String(ApplyController::StatusNeedsApply) && m_pendingLockChange)) {
        m_validationLabel = QStringLiteral("Validation passed — ready to Apply");
        setPhase(QStringLiteral("idle"));
        emit changed();
        return;
    }
    if (st == QLatin1String(ApplyController::StatusValidationFailed)) {
        m_validationLabel = QStringLiteral("Validation failed");
        m_error = m_apply->lastError();
        appendDetails(m_apply->applyLog());
        setPhase(QStringLiteral("error"));
        emit changed();
    }
}
