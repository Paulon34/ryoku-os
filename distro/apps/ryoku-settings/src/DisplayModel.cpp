#include "DisplayModel.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QtMath>
#include <algorithm>
#include <cmath>

Q_LOGGING_CATEGORY(lcDisplay, "ryoku.settings.display")

namespace {
constexpr int kPreviewSeconds = 15;

QString formatModeLabel(int w, int h, double hz)
{
    return QStringLiteral("%1×%2 @ %3 Hz")
        .arg(w)
        .arg(h)
        .arg(QString::number(hz, 'f', hz == std::floor(hz) ? 0 : 2));
}

QString formatRefreshToken(double hz)
{
    // Prefer compact token; keep two decimals when needed (matches hyprland modes).
    if (std::fabs(hz - std::round(hz)) < 0.0005)
        return QString::number(static_cast<int>(std::lround(hz)));
    return QString::number(hz, 'f', 2);
}
} // namespace

DisplayModel::DisplayModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_previewTimer = new QTimer(this);
    m_previewTimer->setSingleShot(true);
    connect(m_previewTimer, &QTimer::timeout, this, [this]() { revertPreview(); });

    m_previewTick = new QTimer(this);
    m_previewTick->setSingleShot(true);
    connect(m_previewTick, &QTimer::timeout, this, &DisplayModel::tickPreview);

    m_hyprctl = findHyprctl();
    checkUnfinishedSnapshot();
    refresh();
}

DisplayModel::~DisplayModel()
{
    // If preview is active on exit, leave snapshot so next launch can recover.
    if (m_previewActive && !m_previewBaseline.isEmpty())
        writeSnapshot(m_previewBaseline);
}

int DisplayModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_monitors.size();
}

QVariant DisplayModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_monitors.size())
        return {};
    const Monitor &m = m_monitors.at(index.row());
    switch (role) {
    case NameRole:
        return m.name;
    case DescriptionRole:
        return m.description;
    case MakeRole:
        return m.make;
    case ModelRole:
        return m.model;
    case WidthRole:
        return m.width;
    case HeightRole:
        return m.height;
    case RefreshRateRole:
        return m.refreshRate;
    case ScaleRole:
        return m.scale;
    case XRole:
        return m.x;
    case YRole:
        return m.y;
    case EnabledRole:
        return m.enabled;
    case FocusedRole:
        return m.focused;
    case ModeLabelRole:
        return formatModeLabel(m.width, m.height, m.refreshRate);
    case AvailableModesRole: {
        QVariantList list;
        for (const Mode &mode : m.availableModes) {
            QVariantMap map;
            map.insert(QStringLiteral("label"), mode.label);
            map.insert(QStringLiteral("width"), mode.width);
            map.insert(QStringLiteral("height"), mode.height);
            map.insert(QStringLiteral("refreshRate"), mode.refreshRate);
            list.append(map);
        }
        return list;
    }
    default:
        return {};
    }
}

QHash<int, QByteArray> DisplayModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {DescriptionRole, "description"},
        {MakeRole, "make"},
        {ModelRole, "model"},
        {WidthRole, "width"},
        {HeightRole, "height"},
        {RefreshRateRole, "refreshRate"},
        {ScaleRole, "scale"},
        {XRole, "x"},
        {YRole, "y"},
        // "displayEnabled" avoids clashing with Item.enabled in QML delegates.
        {EnabledRole, "displayEnabled"},
        {FocusedRole, "focused"},
        {ModeLabelRole, "modeLabel"},
        {AvailableModesRole, "availableModes"},
    };
}

void DisplayModel::setSelectedName(const QString &name)
{
    if (m_selectedName == name)
        return;
    m_selectedName = name;
    emit changed();
}

QVariantMap DisplayModel::selectedDraft() const
{
    const Draft *d = draftForSelected();
    if (!d)
        return {};
    return draftToMap(*d);
}

QVariantList DisplayModel::selectedModeLabels() const
{
    QVariantList labels;
    const Monitor *m = runtimeByName(m_selectedName);
    if (!m)
        return labels;
    for (const Mode &mode : m->availableModes)
        labels.append(mode.label);
    return labels;
}

int DisplayModel::selectedModeIndex() const
{
    const Draft *d = draftForSelected();
    return d ? d->modeIndex : -1;
}

QVariantList DisplayModel::layoutPreview() const
{
    QVariantList out;
    // Prefer draft layout for the canvas when dirty/previewing.
    if (!m_drafts.isEmpty()) {
        for (const Draft &d : m_drafts) {
            if (!d.enabled)
                continue;
            QVariantMap map = draftToMap(d);
            map.insert(QStringLiteral("focused"),
                       runtimeByName(d.name) ? runtimeByName(d.name)->focused : false);
            out.append(map);
        }
        return out;
    }
    for (const Monitor &m : m_monitors) {
        if (!m.enabled)
            continue;
        out.append(monitorToMap(m));
    }
    return out;
}

QString DisplayModel::findHyprctl() const
{
    const QString env = qEnvironmentVariable("RYOKU_HYPRCTL");
    if (!env.isEmpty() && QFile::exists(env))
        return env;
    const QString path = QStandardPaths::findExecutable(QStringLiteral("hyprctl"));
    return path;
}

bool DisplayModel::runHyprctl(const QStringList &args, QByteArray *stdoutOut, QString *errorOut)
{
    if (m_hyprctl.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("hyprctl unavailable");
        return false;
    }
    QProcess proc;
    proc.setProgram(m_hyprctl);
    proc.setArguments(args);
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start();
    if (!proc.waitForFinished(8000)) {
        proc.kill();
        if (errorOut)
            *errorOut = QStringLiteral("hyprctl timed out");
        return false;
    }
    const QByteArray out = proc.readAll();
    if (stdoutOut)
        *stdoutOut = out;
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        if (errorOut) {
            const QString msg = QString::fromUtf8(out).trimmed();
            *errorOut = msg.isEmpty()
                            ? QStringLiteral("hyprctl failed (exit %1)").arg(proc.exitCode())
                            : msg;
        }
        return false;
    }
    return true;
}

void DisplayModel::refresh()
{
    m_error.clear();
    m_hyprctl = findHyprctl();
    if (m_hyprctl.isEmpty()) {
        beginResetModel();
        m_monitors.clear();
        m_drafts.clear();
        endResetModel();
        m_available = false;
        m_error = QStringLiteral("hyprctl unavailable");
        emit changed();
        return;
    }

    // Prefer "all" so disabled outputs remain visible for re-enable.
    QByteArray out;
    QString err;
    if (!runHyprctl({QStringLiteral("monitors"), QStringLiteral("all"), QStringLiteral("-j")}, &out, &err)) {
        // Fallback for older hyprctl.
        if (!runHyprctl({QStringLiteral("monitors"), QStringLiteral("-j")}, &out, &err)) {
            m_available = false;
            m_error = err;
            emit changed();
            return;
        }
    }

    QString parseErr;
    QVector<Monitor> parsed = parseMonitorsJson(out, &parseErr);
    if (!parseErr.isEmpty()) {
        m_available = false;
        m_error = parseErr;
        emit changed();
        return;
    }

    beginResetModel();
    m_monitors = parsed;
    endResetModel();
    m_available = true;

    if (m_selectedName.isEmpty() || !runtimeByName(m_selectedName)) {
        // Prefer focused, else first.
        m_selectedName.clear();
        for (const Monitor &m : m_monitors) {
            if (m.focused) {
                m_selectedName = m.name;
                break;
            }
        }
        if (m_selectedName.isEmpty() && !m_monitors.isEmpty())
            m_selectedName = m_monitors.first().name;
    }

    if (!m_previewActive && !m_draftDirty)
        seedDraftsFromRuntime();

    emit changed();
}

void DisplayModel::seedDraftsFromRuntime()
{
    m_drafts.clear();
    for (const Monitor &m : m_monitors) {
        Draft d;
        d.name = m.name;
        d.enabled = m.enabled;
        d.width = m.width;
        d.height = m.height;
        d.refreshRate = m.refreshRate;
        d.scale = m.scale;
        d.x = m.x;
        d.y = m.y;
        d.modeIndex = findModeIndex(m.availableModes, m.width, m.height, m.refreshRate);
        if (d.modeIndex < 0 && !m.availableModes.isEmpty())
            d.modeIndex = 0;
        m_drafts.append(d);
    }
    m_draftDirty = false;
}

void DisplayModel::resetDraftFromRuntime()
{
    if (m_previewActive) {
        m_statusMessage = tr("Finish or revert preview first");
        emit changed();
        return;
    }
    seedDraftsFromRuntime();
    m_statusMessage.clear();
    emit changed();
}

void DisplayModel::markDraftDirty()
{
    m_draftDirty = true;
    m_statusMessage.clear();
    emit changed();
}

DisplayModel::Draft *DisplayModel::draftForSelected()
{
    for (Draft &d : m_drafts) {
        if (d.name == m_selectedName)
            return &d;
    }
    return nullptr;
}

const DisplayModel::Draft *DisplayModel::draftForSelected() const
{
    for (const Draft &d : m_drafts) {
        if (d.name == m_selectedName)
            return &d;
    }
    return nullptr;
}

const DisplayModel::Monitor *DisplayModel::runtimeByName(const QString &name) const
{
    for (const Monitor &m : m_monitors) {
        if (m.name == name)
            return &m;
    }
    return nullptr;
}

void DisplayModel::setDraftEnabled(bool enabled)
{
    Draft *d = draftForSelected();
    if (!d || m_previewActive)
        return;
    QString err;
    if (!enabled && !canDisableMonitor(m_drafts, d->name, &err)) {
        m_statusMessage = err;
        emit operationFailed(err);
        emit changed();
        return;
    }
    d->enabled = enabled;
    markDraftDirty();
}

void DisplayModel::setDraftModeIndex(int index)
{
    Draft *d = draftForSelected();
    const Monitor *m = runtimeByName(m_selectedName);
    if (!d || !m || m_previewActive)
        return;
    if (index < 0 || index >= m->availableModes.size())
        return;
    const Mode &mode = m->availableModes.at(index);
    d->modeIndex = index;
    d->width = mode.width;
    d->height = mode.height;
    d->refreshRate = mode.refreshRate;
    markDraftDirty();
}

void DisplayModel::setDraftScale(double scale)
{
    Draft *d = draftForSelected();
    if (!d || m_previewActive)
        return;
    QString err;
    if (!validateScale(scale, &err)) {
        m_statusMessage = err;
        emit operationFailed(err);
        emit changed();
        return;
    }
    d->scale = clampScale(scale);
    markDraftDirty();
}

void DisplayModel::setDraftX(int x)
{
    Draft *d = draftForSelected();
    if (!d || m_previewActive)
        return;
    d->x = x;
    markDraftDirty();
}

void DisplayModel::setDraftY(int y)
{
    Draft *d = draftForSelected();
    if (!d || m_previewActive)
        return;
    d->y = y;
    markDraftDirty();
}

void DisplayModel::applyPositionPreset(const QString &preset, const QString &relativeTo)
{
    Draft *d = draftForSelected();
    if (!d || m_previewActive)
        return;
    const Draft *rel = nullptr;
    for (const Draft &other : m_drafts) {
        if (other.name == relativeTo && other.enabled) {
            rel = &other;
            break;
        }
    }
    if (!rel)
        return;

    if (preset == QLatin1String("left")) {
        d->x = rel->x - d->width;
        d->y = rel->y;
    } else if (preset == QLatin1String("right")) {
        d->x = rel->x + rel->width;
        d->y = rel->y;
    } else if (preset == QLatin1String("above")) {
        d->x = rel->x;
        d->y = rel->y - d->height;
    } else if (preset == QLatin1String("below")) {
        d->x = rel->x;
        d->y = rel->y + rel->height;
    } else {
        return;
    }
    markDraftDirty();
}

bool DisplayModel::previewChanges()
{
    if (m_previewActive)
        return false;
    if (!m_available) {
        m_statusMessage = m_error.isEmpty() ? tr("Displays unavailable") : m_error;
        emit operationFailed(m_statusMessage);
        emit changed();
        return false;
    }

    QString err;
    if (!validateLayout(m_drafts, &err)) {
        m_statusMessage = err;
        emit operationFailed(err);
        emit changed();
        return false;
    }

    // Capture complete runtime baseline before touching hyprctl.
    m_previewBaseline = m_monitors;
    if (!writeSnapshot(m_previewBaseline)) {
        m_statusMessage = tr("Failed to write preview snapshot");
        emit operationFailed(m_statusMessage);
        emit changed();
        return false;
    }

    if (!applyDraftLayout(m_drafts, &err)) {
        // Attempt restore immediately on partial failure.
        QString restoreErr;
        applyMonitorList(m_previewBaseline, &restoreErr);
        clearSnapshot();
        m_previewBaseline.clear();
        m_statusMessage = err;
        emit operationFailed(err);
        refresh();
        emit changed();
        return false;
    }

    m_previewActive = true;
    m_previewSecondsLeft = kPreviewSeconds;
    m_statusMessage = tr("Preview active — confirm within 15 seconds");
    startPreviewTimer();
    refresh();
    emit previewStarted();
    emit previewChanged();
    emit changed();
    return true;
}

void DisplayModel::keepChanges()
{
    if (!m_previewActive)
        return;
    stopPreviewTimer(true);
    clearSnapshot();
    m_previewBaseline.clear();
    m_previewActive = false;
    m_previewSecondsLeft = 0;
    m_draftDirty = false;
    m_statusMessage = tr("Runtime applied");
    seedDraftsFromRuntime();
    emit previewEnded(true);
    emit previewChanged();
    emit changed();
}

void DisplayModel::revertPreview()
{
    if (!m_previewActive && m_previewBaseline.isEmpty())
        return;

    stopPreviewTimer(false);
    QString err;
    if (!m_previewBaseline.isEmpty() && !applyMonitorList(m_previewBaseline, &err)) {
        m_statusMessage = tr("Revert failed: %1").arg(err);
        emit operationFailed(m_statusMessage);
    } else {
        m_statusMessage = tr("Preview reverted");
    }
    clearSnapshot();
    m_previewBaseline.clear();
    m_previewActive = false;
    m_previewSecondsLeft = 0;
    m_draftDirty = false;
    refresh();
    seedDraftsFromRuntime();
    emit previewEnded(false);
    emit previewChanged();
    emit changed();
}

bool DisplayModel::restoreUnfinishedPreview()
{
    const QString path = snapshotPath();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        m_unfinishedPreviewAvailable = false;
        emit changed();
        return false;
    }
    QString err;
    const QVector<Monitor> baseline = deserializeSnapshot(f.readAll(), &err);
    f.close();
    if (!err.isEmpty() || baseline.isEmpty()) {
        m_statusMessage = err.isEmpty() ? tr("Invalid preview snapshot") : err;
        emit operationFailed(m_statusMessage);
        emit changed();
        return false;
    }
    if (!applyMonitorList(baseline, &err)) {
        m_statusMessage = tr("Restore failed: %1").arg(err);
        emit operationFailed(m_statusMessage);
        emit changed();
        return false;
    }
    clearSnapshot();
    m_unfinishedPreviewAvailable = false;
    m_statusMessage = tr("Previous layout restored");
    refresh();
    seedDraftsFromRuntime();
    emit changed();
    return true;
}

void DisplayModel::dismissUnfinishedPreview()
{
    clearSnapshot();
    m_unfinishedPreviewAvailable = false;
    emit changed();
}

QVariantList DisplayModel::draftMonitorsForSave() const
{
    QVariantList list;
    for (const Draft &d : m_drafts)
        list.append(draftToMap(d));
    return list;
}

QStringList DisplayModel::otherEnabledMonitorNames() const
{
    QStringList names;
    for (const Draft &d : m_drafts) {
        if (d.name == m_selectedName)
            continue;
        if (d.enabled)
            names.append(d.name);
    }
    return names;
}

bool DisplayModel::applyDraftLayout(const QVector<Draft> &drafts, QString *errorOut)
{
    // Apply enabled monitors first, then disables — reduces blank-screen races.
    QVector<Draft> enabled;
    QVector<Draft> disabled;
    for (const Draft &d : drafts) {
        if (d.enabled)
            enabled.append(d);
        else
            disabled.append(d);
    }

    for (const Draft &d : enabled) {
        const QString value = buildMonitorKeyword(d);
        QString err;
        if (!runHyprctl({QStringLiteral("keyword"), QStringLiteral("monitor"), value}, nullptr, &err)) {
            if (errorOut)
                *errorOut = QStringLiteral("Failed to apply %1: %2").arg(d.name, err);
            return false;
        }
    }
    for (const Draft &d : disabled) {
        const QString value = QStringLiteral("%1,disable").arg(d.name);
        QString err;
        if (!runHyprctl({QStringLiteral("keyword"), QStringLiteral("monitor"), value}, nullptr, &err)) {
            if (errorOut)
                *errorOut = QStringLiteral("Failed to disable %1: %2").arg(d.name, err);
            return false;
        }
    }
    return true;
}

bool DisplayModel::applyMonitorList(const QVector<Monitor> &monitors, QString *errorOut)
{
    QVector<Draft> drafts;
    for (const Monitor &m : monitors) {
        Draft d;
        d.name = m.name;
        d.enabled = m.enabled;
        d.width = m.width;
        d.height = m.height;
        d.refreshRate = m.refreshRate;
        d.scale = m.scale;
        d.x = m.x;
        d.y = m.y;
        drafts.append(d);
    }
    return applyDraftLayout(drafts, errorOut);
}

QString DisplayModel::snapshotPath() const
{
    const QString runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    return QDir(runtime).filePath(QStringLiteral("ryoku-settings/display-preview.json"));
}

bool DisplayModel::writeSnapshot(const QVector<Monitor> &monitors)
{
    const QString path = snapshotPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    const QByteArray data = serializeSnapshot(monitors);
    return f.write(data) == data.size();
}

bool DisplayModel::clearSnapshot()
{
    const QString path = snapshotPath();
    if (!QFile::exists(path))
        return true;
    return QFile::remove(path);
}

void DisplayModel::checkUnfinishedSnapshot()
{
    const QString path = snapshotPath();
    m_unfinishedPreviewAvailable = QFile::exists(path);
}

void DisplayModel::startPreviewTimer()
{
    m_previewTimer->start(kPreviewSeconds * 1000);
    m_previewTick->start(1000);
}

void DisplayModel::stopPreviewTimer(bool /*kept*/)
{
    m_previewTimer->stop();
    m_previewTick->stop();
}

void DisplayModel::tickPreview()
{
    if (!m_previewActive)
        return;
    m_previewSecondsLeft = qMax(0, m_previewSecondsLeft - 1);
    emit previewChanged();
    if (m_previewSecondsLeft > 0)
        m_previewTick->start(1000);
}

QVariantMap DisplayModel::monitorToMap(const Monitor &m) const
{
    QVariantMap map;
    map.insert(QStringLiteral("name"), m.name);
    map.insert(QStringLiteral("description"), m.description);
    map.insert(QStringLiteral("make"), m.make);
    map.insert(QStringLiteral("model"), m.model);
    map.insert(QStringLiteral("enabled"), m.enabled);
    map.insert(QStringLiteral("width"), m.width);
    map.insert(QStringLiteral("height"), m.height);
    map.insert(QStringLiteral("refreshRate"), m.refreshRate);
    map.insert(QStringLiteral("scale"), m.scale);
    map.insert(QStringLiteral("x"), m.x);
    map.insert(QStringLiteral("y"), m.y);
    map.insert(QStringLiteral("focused"), m.focused);
    return map;
}

QVariantMap DisplayModel::draftToMap(const Draft &d) const
{
    QVariantMap map;
    map.insert(QStringLiteral("name"), d.name);
    map.insert(QStringLiteral("enabled"), d.enabled);
    map.insert(QStringLiteral("width"), d.width);
    map.insert(QStringLiteral("height"), d.height);
    map.insert(QStringLiteral("refreshRate"), d.refreshRate);
    map.insert(QStringLiteral("scale"), d.scale);
    map.insert(QStringLiteral("x"), d.x);
    map.insert(QStringLiteral("y"), d.y);
    map.insert(QStringLiteral("modeIndex"), d.modeIndex);
    return map;
}

// --- static helpers ---

bool DisplayModel::parseModeToken(const QString &token, Mode *out)
{
    if (!out)
        return false;
    static const QRegularExpression re(
        QStringLiteral(R"(^(\d+)x(\d+)@([\d.]+)Hz$)"),
        QRegularExpression::CaseInsensitiveOption);
    const auto match = re.match(token.trimmed());
    if (!match.hasMatch())
        return false;
    out->width = match.captured(1).toInt();
    out->height = match.captured(2).toInt();
    out->refreshRate = match.captured(3).toDouble();
    out->raw = token.trimmed();
    out->label = formatModeLabel(out->width, out->height, out->refreshRate);
    return out->width > 0 && out->height > 0 && out->refreshRate > 0.0;
}

bool DisplayModel::modeMatches(const Mode &mode, int width, int height, double refresh)
{
    return mode.width == width && mode.height == height
           && std::fabs(mode.refreshRate - refresh) < 0.05;
}

int DisplayModel::findModeIndex(const QVector<Mode> &modes, int width, int height, double refresh)
{
    for (int i = 0; i < modes.size(); ++i) {
        if (modeMatches(modes.at(i), width, height, refresh))
            return i;
    }
    // Looser match: same WxH, closest refresh.
    int best = -1;
    double bestDelta = 1e9;
    for (int i = 0; i < modes.size(); ++i) {
        const Mode &m = modes.at(i);
        if (m.width != width || m.height != height)
            continue;
        const double delta = std::fabs(m.refreshRate - refresh);
        if (delta < bestDelta) {
            bestDelta = delta;
            best = i;
        }
    }
    return best;
}

double DisplayModel::clampScale(double scale)
{
    return qBound(0.5, scale, 3.0);
}

bool DisplayModel::validateScale(double scale, QString *errorOut)
{
    if (scale < 0.5 || scale > 3.0) {
        if (errorOut)
            *errorOut = QStringLiteral("Scale must be between 0.5 and 3.0");
        return false;
    }
    return true;
}

bool DisplayModel::canDisableMonitor(const QVector<Draft> &drafts, const QString &name, QString *errorOut)
{
    int enabledCount = 0;
    bool targetEnabled = false;
    for (const Draft &d : drafts) {
        if (d.enabled)
            ++enabledCount;
        if (d.name == name)
            targetEnabled = d.enabled;
    }
    if (targetEnabled && enabledCount <= 1) {
        if (errorOut)
            *errorOut = QStringLiteral("Cannot disable the last active monitor");
        return false;
    }
    return true;
}

bool DisplayModel::validateLayout(const QVector<Draft> &drafts, QString *errorOut)
{
    int enabled = 0;
    for (const Draft &d : drafts) {
        if (d.name.trimmed().isEmpty()) {
            if (errorOut)
                *errorOut = QStringLiteral("Invalid monitor name");
            return false;
        }
        if (!validateScale(d.scale, errorOut))
            return false;
        if (d.enabled) {
            ++enabled;
            if (d.width <= 0 || d.height <= 0 || d.refreshRate <= 0.0) {
                if (errorOut)
                    *errorOut = QStringLiteral("Unsupported or incomplete mode for %1").arg(d.name);
                return false;
            }
        }
    }
    if (enabled < 1) {
        if (errorOut)
            *errorOut = QStringLiteral("At least one monitor must remain enabled");
        return false;
    }
    return true;
}

QString DisplayModel::buildMonitorKeyword(const Draft &d)
{
    if (!d.enabled)
        return QStringLiteral("%1,disable").arg(d.name);
    return QStringLiteral("%1,%2x%3@%4,%5x%6,%7")
        .arg(d.name)
        .arg(d.width)
        .arg(d.height)
        .arg(formatRefreshToken(d.refreshRate))
        .arg(d.x)
        .arg(d.y)
        .arg(QString::number(d.scale, 'g', 4));
}

QVector<DisplayModel::Monitor> DisplayModel::parseMonitorsJson(const QByteArray &json, QString *errorOut)
{
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isArray()) {
        if (errorOut)
            *errorOut = QStringLiteral("Invalid monitors JSON");
        return {};
    }

    QVector<Monitor> out;
    const QJsonArray arr = doc.array();
    for (const QJsonValue &v : arr) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        Monitor m;
        m.name = o.value(QStringLiteral("name")).toString();
        if (m.name.isEmpty())
            continue;
        m.description = o.value(QStringLiteral("description")).toString();
        m.make = o.value(QStringLiteral("make")).toString();
        m.model = o.value(QStringLiteral("model")).toString();
        m.width = o.value(QStringLiteral("width")).toInt();
        m.height = o.value(QStringLiteral("height")).toInt();
        m.refreshRate = o.value(QStringLiteral("refreshRate")).toDouble();
        m.scale = o.value(QStringLiteral("scale")).toDouble(1.0);
        m.x = o.value(QStringLiteral("x")).toInt();
        m.y = o.value(QStringLiteral("y")).toInt();
        m.focused = o.value(QStringLiteral("focused")).toBool();
        m.enabled = !o.value(QStringLiteral("disabled")).toBool();

        const QJsonArray modes = o.value(QStringLiteral("availableModes")).toArray();
        QSet<QString> seen;
        for (const QJsonValue &mv : modes) {
            Mode mode;
            if (!parseModeToken(mv.toString(), &mode))
                continue;
            const QString key = QStringLiteral("%1x%2@%3")
                                    .arg(mode.width)
                                    .arg(mode.height)
                                    .arg(QString::number(mode.refreshRate, 'f', 2));
            if (seen.contains(key))
                continue;
            seen.insert(key);
            m.availableModes.append(mode);
        }
        // Ensure current mode exists in list for UI selection.
        if (m.enabled && m.width > 0 && m.height > 0 && m.refreshRate > 0.0) {
            if (findModeIndex(m.availableModes, m.width, m.height, m.refreshRate) < 0) {
                Mode cur;
                cur.width = m.width;
                cur.height = m.height;
                cur.refreshRate = m.refreshRate;
                cur.label = formatModeLabel(cur.width, cur.height, cur.refreshRate);
                m.availableModes.prepend(cur);
            }
        }
        out.append(m);
    }

    if (out.isEmpty() && errorOut)
        *errorOut = QStringLiteral("No monitors reported");
    return out;
}

QByteArray DisplayModel::serializeSnapshot(const QVector<Monitor> &monitors)
{
    QJsonArray arr;
    for (const Monitor &m : monitors) {
        QJsonObject o;
        o.insert(QStringLiteral("name"), m.name);
        o.insert(QStringLiteral("description"), m.description);
        o.insert(QStringLiteral("make"), m.make);
        o.insert(QStringLiteral("model"), m.model);
        o.insert(QStringLiteral("width"), m.width);
        o.insert(QStringLiteral("height"), m.height);
        o.insert(QStringLiteral("refreshRate"), m.refreshRate);
        o.insert(QStringLiteral("scale"), m.scale);
        o.insert(QStringLiteral("x"), m.x);
        o.insert(QStringLiteral("y"), m.y);
        o.insert(QStringLiteral("enabled"), m.enabled);
        o.insert(QStringLiteral("focused"), m.focused);
        arr.append(o);
    }
    QJsonObject root;
    root.insert(QStringLiteral("version"), 1);
    root.insert(QStringLiteral("monitors"), arr);
    return QJsonDocument(root).toJson(QJsonDocument::Indented);
}

QVector<DisplayModel::Monitor> DisplayModel::deserializeSnapshot(const QByteArray &json, QString *errorOut)
{
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut)
            *errorOut = QStringLiteral("Invalid snapshot JSON");
        return {};
    }
    const QJsonArray arr = doc.object().value(QStringLiteral("monitors")).toArray();
    QVector<Monitor> out;
    for (const QJsonValue &v : arr) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        Monitor m;
        m.name = o.value(QStringLiteral("name")).toString();
        if (m.name.isEmpty())
            continue;
        m.description = o.value(QStringLiteral("description")).toString();
        m.make = o.value(QStringLiteral("make")).toString();
        m.model = o.value(QStringLiteral("model")).toString();
        m.width = o.value(QStringLiteral("width")).toInt();
        m.height = o.value(QStringLiteral("height")).toInt();
        m.refreshRate = o.value(QStringLiteral("refreshRate")).toDouble();
        m.scale = o.value(QStringLiteral("scale")).toDouble(1.0);
        m.x = o.value(QStringLiteral("x")).toInt();
        m.y = o.value(QStringLiteral("y")).toInt();
        m.enabled = o.value(QStringLiteral("enabled")).toBool(true);
        m.focused = o.value(QStringLiteral("focused")).toBool();
        out.append(m);
    }
    if (out.isEmpty() && errorOut)
        *errorOut = QStringLiteral("Empty snapshot");
    return out;
}
