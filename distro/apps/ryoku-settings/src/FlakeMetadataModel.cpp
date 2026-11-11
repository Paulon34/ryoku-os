#include "FlakeMetadataModel.h"

#include <QDateTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLoggingCategory>
#include <QProcess>

Q_LOGGING_CATEGORY(lcFlakeMeta, "ryoku.settings.flake")

FlakeMetadataModel::FlakeMetadataModel(QObject *parent)
    : QObject(parent)
{
}

FlakeMetadataModel::~FlakeMetadataModel()
{
    if (m_process) {
        m_process->kill();
        m_process->waitForFinished(500);
    }
}

void FlakeMetadataModel::setRepoPath(const QString &path)
{
    if (m_repoPath == path)
        return;
    m_repoPath = path;
    emit repoPathChanged();
}

void FlakeMetadataModel::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
}

void FlakeMetadataModel::refreshLockFileInfo(const QString &repoPath, bool *present, QString *modifiedLabel)
{
    if (present)
        *present = false;
    if (modifiedLabel)
        *modifiedLabel = QStringLiteral("Unavailable");
    if (repoPath.isEmpty())
        return;
    const QFileInfo fi(repoPath + QStringLiteral("/flake.lock"));
    if (!fi.exists())
        return;
    if (present)
        *present = true;
    if (modifiedLabel)
        *modifiedLabel = fi.lastModified().toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm"));
}

QVariantList FlakeMetadataModel::extractInputs(const QVariantMap &root)
{
    QVariantList out;
    const QVariantMap locks = root.value(QStringLiteral("locks")).toMap();
    const QVariantMap nodes = locks.value(QStringLiteral("nodes")).toMap();
    const QVariantMap rootNode = nodes.value(QStringLiteral("root")).toMap();
    const QVariantMap inputsMap = rootNode.value(QStringLiteral("inputs")).toMap();

    QStringList names = inputsMap.keys();
    names.sort(Qt::CaseInsensitive);
    for (const QString &name : names) {
        QVariantMap row;
        row.insert(QStringLiteral("name"), name);
        const QString nodeKey = inputsMap.value(name).toString();
        QString summary = nodeKey;
        if (!nodeKey.isEmpty() && nodes.contains(nodeKey)) {
            const QVariantMap node = nodes.value(nodeKey).toMap();
            const QVariantMap locked = node.value(QStringLiteral("locked")).toMap();
            const QString type = locked.value(QStringLiteral("type")).toString();
            if (type == QLatin1String("github") || type == QLatin1String("gitlab")) {
                const QString owner = locked.value(QStringLiteral("owner")).toString();
                const QString repo = locked.value(QStringLiteral("repo")).toString();
                const QString rev = locked.value(QStringLiteral("rev")).toString().left(7);
                summary = QStringLiteral("%1/%2@%3").arg(owner, repo, rev.isEmpty() ? QStringLiteral("?") : rev);
            } else if (type == QLatin1String("indirect")) {
                summary = locked.value(QStringLiteral("id")).toString();
            } else if (!type.isEmpty()) {
                summary = type;
            }
        }
        row.insert(QStringLiteral("summary"), summary);
        out.append(row);
    }
    return out;
}

QVariantMap FlakeMetadataModel::parseMetadataJson(const QByteArray &json, QString *errorOut)
{
    QVariantMap out;
    if (errorOut)
        errorOut->clear();
    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut)
            *errorOut = pe.error != QJsonParseError::NoError
                            ? pe.errorString()
                            : QStringLiteral("Expected JSON object");
        return {};
    }
    const QJsonObject obj = doc.object();
    out.insert(QStringLiteral("url"), obj.value(QStringLiteral("url")).toString());
    out.insert(QStringLiteral("description"), obj.value(QStringLiteral("description")).toString());
    // Convert locks subtree via toVariantMap for extractInputs
    out.insert(QStringLiteral("locks"), obj.value(QStringLiteral("locks")).toVariant().toMap());
    const QVariantList inputs = extractInputs(out);
    out.insert(QStringLiteral("inputs"), inputs);
    out.insert(QStringLiteral("lockedInputCount"), inputs.size());
    return out;
}

void FlakeMetadataModel::applyParsed(const QVariantMap &parsed)
{
    m_flakeUrl = parsed.value(QStringLiteral("url")).toString();
    m_description = parsed.value(QStringLiteral("description")).toString();
    m_inputs = parsed.value(QStringLiteral("inputs")).toList();
    m_lockedInputCount = parsed.value(QStringLiteral("lockedInputCount")).toInt();
    m_available = true;
    m_error.clear();
}

void FlakeMetadataModel::refresh()
{
    refreshLockFileInfo(m_repoPath, &m_lockPresent, &m_lockLastModified);

    if (m_repoPath.isEmpty()) {
        m_available = false;
        m_error = QStringLiteral("Repository path unavailable");
        m_details.clear();
        m_inputs.clear();
        m_lockedInputCount = 0;
        emit changed();
        return;
    }

    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &FlakeMetadataModel::onFinished);
    }
    if (m_process->state() != QProcess::NotRunning)
        return;

    setBusy(true);
    m_error.clear();
    m_details.clear();
    emit changed();

    m_process->setProgram(QStringLiteral("nix"));
    m_process->setArguments({QStringLiteral("flake"), QStringLiteral("metadata"),
                             QStringLiteral("--json"), QStringLiteral(".")});
    m_process->setWorkingDirectory(m_repoPath);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->start();
}

void FlakeMetadataModel::onFinished(int exitCode, QProcess::ExitStatus status)
{
    setBusy(false);
    if (!m_process)
        return;
    const QByteArray out = m_process->readAllStandardOutput();
    const QByteArray err = m_process->readAllStandardError();
    m_details = QString::fromUtf8(err).trimmed().left(2000);

    if (status != QProcess::NormalExit || exitCode != 0) {
        m_available = false;
        m_error = QStringLiteral("flake metadata failed");
        qWarning(lcFlakeMeta) << "nix flake metadata failed" << exitCode << m_details;
        emit changed();
        return;
    }

    QString parseErr;
    const QVariantMap parsed = parseMetadataJson(out, &parseErr);
    if (parsed.isEmpty()) {
        m_available = false;
        m_error = parseErr.isEmpty() ? QStringLiteral("Invalid metadata JSON") : parseErr;
        emit changed();
        return;
    }

    applyParsed(parsed);
    emit changed();
}
