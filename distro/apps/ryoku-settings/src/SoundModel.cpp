#include "SoundModel.h"

#include <QFileInfo>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantMap>

Q_LOGGING_CATEGORY(lcSound, "ryoku.settings.sound")

SoundModel::SoundModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_wpctl = findWpctl();
    m_available = !m_wpctl.isEmpty();
    if (!m_available)
        m_error = QStringLiteral("wpctl not found (PipeWire/WirePlumber)");
    else
        refresh();
}

SoundModel::~SoundModel() = default;

int SoundModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_nodes.size();
}

QVariant SoundModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_nodes.size())
        return {};
    const Node &n = m_nodes.at(index.row());
    switch (role) {
    case IdRole:
        return n.id;
    case NameRole:
        return n.name;
    case IsDefaultRole:
        return n.isDefault;
    case IsSinkRole:
        return n.isSink;
    default:
        return {};
    }
}

QHash<int, QByteArray> SoundModel::roleNames() const
{
    return {
        {IdRole, "nodeId"},
        {NameRole, "name"},
        {IsDefaultRole, "isDefault"},
        {IsSinkRole, "isSink"},
    };
}

int SoundModel::clampVolume(int percent)
{
    return qBound(0, percent, 150); // wpctl allows >100; UI uses 0–100 primarily
}

bool SoundModel::parseVolumeLine(const QByteArray &line, int *volumeOut, bool *mutedOut)
{
    // Typical: "Volume: 0.40" or "Volume: 0.40 [MUTED]"
    const QString s = QString::fromUtf8(line).trimmed();
    static const QRegularExpression re(QStringLiteral(R"(Volume:\s*([0-9]*\.?[0-9]+))"));
    const auto m = re.match(s);
    if (!m.hasMatch())
        return false;
    const double v = m.captured(1).toDouble();
    if (volumeOut)
        *volumeOut = clampVolume(qRound(v * 100.0));
    if (mutedOut)
        *mutedOut = s.contains(QStringLiteral("MUTED"), Qt::CaseInsensitive);
    return true;
}

QVector<SoundModel::Node> SoundModel::parseWpctlStatus(const QByteArray &text, bool sinks)
{
    QVector<Node> out;
    const QStringList lines = QString::fromUtf8(text).split(QLatin1Char('\n'));
    bool inSection = false;
    const QString sectionNeedle = sinks ? QStringLiteral("Sinks:") : QStringLiteral("Sources:");
    // Flexible: optional tree glyphs, optional '*', id, name.
    static const QRegularExpression nodeRe(
        QStringLiteral("(\\*)?\\s*(\\d+)\\.\\s+(.+)$"));

    for (const QString &rawLine : lines) {
        const QString line = rawLine;
        if (line.contains(sectionNeedle)) {
            inSection = true;
            continue;
        }
        if (!inSection)
            continue;

        const QString trimmed = line.trimmed();
        // Leave section on next top-level audio header.
        if (trimmed.endsWith(QLatin1Char(':'))) {
            if (trimmed.contains(QStringLiteral("Sinks")) || trimmed.contains(QStringLiteral("Sources"))
                || trimmed.contains(QStringLiteral("Filters")) || trimmed.contains(QStringLiteral("Streams"))
                || trimmed.contains(QStringLiteral("Video"))) {
                if (!trimmed.contains(sectionNeedle))
                    break;
            }
        }

        const auto m = nodeRe.match(line);
        if (!m.hasMatch())
            continue;
        Node n;
        n.isDefault = !m.captured(1).isEmpty();
        n.id = m.captured(2).toUInt();
        n.name = m.captured(3).trimmed();
        const int bracket = n.name.indexOf(QLatin1Char('['));
        if (bracket > 0)
            n.name = n.name.left(bracket).trimmed();
        n.isSink = sinks;
        if (n.id > 0 && !n.name.isEmpty())
            out.append(n);
    }
    return out;
}

QString SoundModel::findWpctl() const
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("wpctl"));
    if (!fromPath.isEmpty())
        return fromPath;
    const QString systemPath = QStringLiteral("/run/current-system/sw/bin/wpctl");
    if (QFileInfo::exists(systemPath) && QFileInfo(systemPath).isExecutable())
        return systemPath;
    return {};
}

bool SoundModel::runWpctl(const QStringList &args, QByteArray *stdoutOut, QString *errorOut)
{
    if (m_wpctl.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("wpctl not found");
        return false;
    }
    QProcess proc;
    proc.setProgram(m_wpctl);
    proc.setArguments(args);
    proc.setProcessChannelMode(QProcess::SeparateChannels);
    proc.start();
    if (!proc.waitForFinished(5000)) {
        proc.kill();
        if (errorOut)
            *errorOut = QStringLiteral("wpctl timed out");
        return false;
    }
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        if (errorOut) {
            *errorOut = QString::fromUtf8(proc.readAllStandardError()).trimmed();
            if (errorOut->isEmpty())
                *errorOut = QStringLiteral("wpctl failed");
        }
        return false;
    }
    if (stdoutOut)
        *stdoutOut = proc.readAllStandardOutput();
    return true;
}

void SoundModel::refresh()
{
    m_wpctl = findWpctl();
    m_available = !m_wpctl.isEmpty();
    if (!m_available) {
        m_error = QStringLiteral("wpctl not found (PipeWire/WirePlumber)");
        beginResetModel();
        m_nodes.clear();
        endResetModel();
        emit changed();
        return;
    }
    m_error.clear();

    QByteArray statusOut;
    QString err;
    if (!runWpctl({QStringLiteral("status")}, &statusOut, &err)) {
        m_error = err;
        emit changed();
        return;
    }

    QByteArray volOut;
    if (runWpctl({QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, &volOut, &err)) {
        int vol = m_outputVolume;
        bool muted = m_outputMuted;
        if (parseVolumeLine(volOut, &vol, &muted)) {
            m_outputVolume = vol;
            m_outputMuted = muted;
        }
    }
    volOut.clear();
    if (runWpctl({QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@")}, &volOut, &err)) {
        int vol = m_inputVolume;
        bool muted = m_inputMuted;
        if (parseVolumeLine(volOut, &vol, &muted)) {
            m_inputVolume = vol;
            m_inputMuted = muted;
        }
    }

    const QVector<Node> sinks = parseWpctlStatus(statusOut, true);
    const QVector<Node> sources = parseWpctlStatus(statusOut, false);
    m_defaultOutputName.clear();
    m_defaultInputName.clear();
    m_sinkDevices.clear();
    m_sourceDevices.clear();
    for (const Node &n : sinks) {
        if (n.isDefault)
            m_defaultOutputName = n.name;
        m_sinkDevices.append(QVariantMap{
            {QStringLiteral("nodeId"), n.id},
            {QStringLiteral("name"), n.name},
            {QStringLiteral("isDefault"), n.isDefault},
        });
    }
    for (const Node &n : sources) {
        if (n.isDefault)
            m_defaultInputName = n.name;
        m_sourceDevices.append(QVariantMap{
            {QStringLiteral("nodeId"), n.id},
            {QStringLiteral("name"), n.name},
            {QStringLiteral("isDefault"), n.isDefault},
        });
    }

    beginResetModel();
    m_nodes = sinks;
    endResetModel();
    emit changed();
}

void SoundModel::setOutputVolume(int percent)
{
    const int v = clampVolume(percent);
    QString err;
    if (!runWpctl({QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                   QStringLiteral("%1%%").arg(v)},
                  nullptr, &err)) {
        emit operationFailed(err);
        return;
    }
    m_outputVolume = v;
    emit changed();
}

void SoundModel::setInputVolume(int percent)
{
    const int v = clampVolume(percent);
    QString err;
    if (!runWpctl({QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@"),
                   QStringLiteral("%1%%").arg(v)},
                  nullptr, &err)) {
        emit operationFailed(err);
        return;
    }
    m_inputVolume = v;
    emit changed();
}

void SoundModel::scheduleOutputVolume(int percent)
{
    m_pendingOutput = clampVolume(percent);
    m_outputVolume = m_pendingOutput; // optimistic UI
    emit changed();
    if (!m_volumeDebounce) {
        m_volumeDebounce = new QTimer(this);
        m_volumeDebounce->setSingleShot(true);
        m_volumeDebounce->setInterval(80);
        connect(m_volumeDebounce, &QTimer::timeout, this, &SoundModel::applyPendingVolumes);
    }
    m_volumeDebounce->start();
}

void SoundModel::scheduleInputVolume(int percent)
{
    m_pendingInput = clampVolume(percent);
    m_inputVolume = m_pendingInput;
    emit changed();
    if (!m_volumeDebounce) {
        m_volumeDebounce = new QTimer(this);
        m_volumeDebounce->setSingleShot(true);
        m_volumeDebounce->setInterval(80);
        connect(m_volumeDebounce, &QTimer::timeout, this, &SoundModel::applyPendingVolumes);
    }
    m_volumeDebounce->start();
}

void SoundModel::applyPendingVolumes()
{
    if (m_pendingOutput >= 0) {
        const int v = m_pendingOutput;
        m_pendingOutput = -1;
        setOutputVolume(v);
    }
    if (m_pendingInput >= 0) {
        const int v = m_pendingInput;
        m_pendingInput = -1;
        setInputVolume(v);
    }
}

void SoundModel::setOutputMuted(bool muted)
{
    QString err;
    if (!runWpctl({QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                   muted ? QStringLiteral("1") : QStringLiteral("0")},
                  nullptr, &err)) {
        emit operationFailed(err);
        return;
    }
    m_outputMuted = muted;
    emit changed();
}

void SoundModel::setInputMuted(bool muted)
{
    QString err;
    if (!runWpctl({QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SOURCE@"),
                   muted ? QStringLiteral("1") : QStringLiteral("0")},
                  nullptr, &err)) {
        emit operationFailed(err);
        return;
    }
    m_inputMuted = muted;
    emit changed();
}

void SoundModel::setDefaultSink(quint32 id)
{
    QString err;
    if (!runWpctl({QStringLiteral("set-default"), QString::number(id)}, nullptr, &err)) {
        emit operationFailed(err);
        return;
    }
    refresh();
}

void SoundModel::setDefaultSource(quint32 id)
{
    QString err;
    if (!runWpctl({QStringLiteral("set-default"), QString::number(id)}, nullptr, &err)) {
        emit operationFailed(err);
        return;
    }
    refresh();
}
