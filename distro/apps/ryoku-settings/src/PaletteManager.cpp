#include "PaletteManager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QStandardPaths>
#include <QTimer>

#include <cstdlib>

Q_LOGGING_CATEGORY(lcPalette, "ryoku.settings.palette")

namespace {

// Embedded dark recovery palette — NOT a second source of truth.
// High-contrast Material-style dark so the UI stays legible without palette.json.
constexpr const char *kFallbackJson = R"({
  "mode": "dark",
  "primary": "#a8c8ff",
  "on_primary": "#00315f",
  "secondary": "#b8c8e0",
  "on_secondary": "#223148",
  "tertiary": "#d1bce0",
  "on_tertiary": "#372c41",
  "background": "#111318",
  "on_background": "#e2e2e9",
  "surface": "#111318",
  "on_surface": "#e2e2e9",
  "surface_variant": "#43474e",
  "surface_container": "#1d2024",
  "surface_container_high": "#282a2f",
  "outline": "#8d9199",
  "error": "#ffb4ab",
  "on_error": "#690005"
})";

struct ColorMapEntry {
    QColor *field;
    const char *jsonKey; // snake_case as written by Matugen / ryoku-palette.json
};

bool readColor(const QJsonObject &obj, const char *key, QColor *out, QString *errorOut)
{
    if (!obj.contains(QLatin1String(key))) {
        // Optional soft-fill keys are handled by caller with defaults.
        return false;
    }
    const QJsonValue v = obj.value(QLatin1String(key));
    if (!v.isString()) {
        if (errorOut)
            *errorOut = QStringLiteral("invalid color: %1 (not a string)").arg(QLatin1String(key));
        return false;
    }
    const QColor c(v.toString());
    if (!c.isValid()) {
        if (errorOut)
            *errorOut = QStringLiteral("invalid color: %1 (%2)").arg(QLatin1String(key), v.toString());
        return false;
    }
    *out = c;
    return true;
}

} // namespace

QString PaletteManager::resolvePalettePath()
{
    // Prefer explicit XDG / HOME so we never depend only on Qt's ConfigLocation
    // (which can differ under wrappers). Same file Matugen writes.
    const auto candidate = [](const QString &base) -> QString {
        if (base.isEmpty())
            return {};
        return QDir(base).filePath(QStringLiteral("ryoku/palette.json"));
    };

    QStringList bases;
    if (const char *xdg = std::getenv("XDG_CONFIG_HOME")) {
        const QString v = QString::fromLocal8Bit(xdg).trimmed();
        if (!v.isEmpty())
            bases.append(v);
    }
    bases.append(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation));
    if (const char *home = std::getenv("HOME")) {
        const QString v = QString::fromLocal8Bit(home).trimmed();
        if (!v.isEmpty())
            bases.append(QDir(v).filePath(QStringLiteral(".config")));
    }
    bases.append(QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
                     .filePath(QStringLiteral(".config")));

    QString firstExisting;
    for (const QString &base : bases) {
        const QString path = candidate(base);
        if (path.isEmpty())
            continue;
        if (QFileInfo::exists(path))
            return QFileInfo(path).absoluteFilePath();
        if (firstExisting.isEmpty())
            firstExisting = QFileInfo(path).absoluteFilePath();
    }
    // Return preferred path even if missing (for warnings / watcher parent).
    return firstExisting;
}

PaletteManager::PaletteManager(QObject *parent)
    : QObject(parent)
{
    m_palettePath = resolvePalettePath();
    logDiagnostics(QStringLiteral("construct/pre-load"));
    // Seed embedded fallback colors so properties are always valid, then try disk.
    applyFallback(QString());
    reload();
    logDiagnostics(QStringLiteral("construct/post-load"));
    watchPaletteFile();
}

void PaletteManager::logDiagnostics(const QString &phase) const
{
    const QString home = qEnvironmentVariable("HOME");
    const QString configLoc = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    const QFileInfo fi(m_palettePath);

    // Plain qInfo (not categorized) so startup diagnostics always appear without
    // QT_LOGGING_RULES — temporary Phase 7B verification aid.
    qInfo().noquote() << "[ryoku.settings.palette] ===" << phase << "===";
    qInfo().noquote() << "[ryoku.settings.palette] HOME=" << home;
    qInfo().noquote() << "[ryoku.settings.palette] ConfigLocation=" << configLoc;
    qInfo().noquote() << "[ryoku.settings.palette] palettePath=" << m_palettePath;
    qInfo().noquote() << "[ryoku.settings.palette] exists=" << fi.exists()
                       << "readable=" << fi.isReadable()
                       << "size=" << fi.size();
    qInfo().noquote() << "[ryoku.settings.palette] usingFallback=" << m_usingFallback
                       << "fallbackReason="
                       << (m_warning.isEmpty() ? QStringLiteral("(none)") : m_warning);
    qInfo().noquote() << "[ryoku.settings.palette] colors:"
                       << "primary=" << m_primary.name()
                       << "onPrimary=" << m_onPrimary.name()
                       << "background=" << m_background.name()
                       << "onBackground=" << m_onBackground.name()
                       << "surface=" << m_surface.name()
                       << "onSurface=" << m_onSurface.name()
                       << "surfaceContainer=" << m_surfaceContainer.name();
}

void PaletteManager::applyFallback(const QString &reason)
{
    QString err;
    parsePaletteJson(QByteArray(kFallbackJson), this, &err);
    m_usingFallback = true;
    // Empty reason = silent seed during construction before first reload.
    m_warning = reason;
    emit paletteChanged();
}

bool PaletteManager::parsePaletteJson(const QByteArray &json, PaletteManager *target, QString *errorOut)
{
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut) {
            *errorOut = err.errorString().isEmpty()
                ? QStringLiteral("invalid JSON")
                : QStringLiteral("invalid JSON: %1").arg(err.errorString());
        }
        return false;
    }

    const QJsonObject obj = doc.object();

    // Required keys (Matugen ryoku-palette.json snake_case).
    for (const char *required : {"primary", "background", "on_surface"}) {
        if (!obj.contains(QLatin1String(required))) {
            if (errorOut)
                *errorOut = QStringLiteral("missing required key: %1").arg(QLatin1String(required));
            return false;
        }
    }

    // Soft defaults = embedded fallback (high contrast dark).
    QColor primary = QColor(QStringLiteral("#a8c8ff"));
    QColor onPrimary = QColor(QStringLiteral("#00315f"));
    QColor secondary = QColor(QStringLiteral("#b8c8e0"));
    QColor onSecondary = QColor(QStringLiteral("#223148"));
    QColor tertiary = QColor(QStringLiteral("#d1bce0"));
    QColor onTertiary = QColor(QStringLiteral("#372c41"));
    QColor background = QColor(QStringLiteral("#111318"));
    QColor onBackground = QColor(QStringLiteral("#e2e2e9"));
    QColor surface = QColor(QStringLiteral("#111318"));
    QColor onSurface = QColor(QStringLiteral("#e2e2e9"));
    QColor surfaceVariant = QColor(QStringLiteral("#43474e"));
    QColor surfaceContainer = QColor(QStringLiteral("#1d2024"));
    QColor surfaceContainerHigh = QColor(QStringLiteral("#282a2f"));
    QColor outline = QColor(QStringLiteral("#8d9199"));
    QColor error = QColor(QStringLiteral("#ffb4ab"));
    QColor onError = QColor(QStringLiteral("#690005"));

    // Explicit snake_case → camelCase field mapping (Matugen format unchanged).
    const ColorMapEntry map[] = {
        {&primary, "primary"},
        {&onPrimary, "on_primary"},
        {&secondary, "secondary"},
        {&onSecondary, "on_secondary"},
        {&tertiary, "tertiary"},
        {&onTertiary, "on_tertiary"},
        {&background, "background"},
        {&onBackground, "on_background"},
        {&surface, "surface"},
        {&onSurface, "on_surface"},
        {&surfaceVariant, "surface_variant"},
        {&surfaceContainer, "surface_container"},
        {&surfaceContainerHigh, "surface_container_high"},
        {&outline, "outline"},
        {&error, "error"},
        {&onError, "on_error"},
    };

    for (const ColorMapEntry &entry : map) {
        QString colorErr;
        if (obj.contains(QLatin1String(entry.jsonKey))) {
            if (!readColor(obj, entry.jsonKey, entry.field, &colorErr)) {
                if (errorOut)
                    *errorOut = colorErr;
                return false;
            }
        }
    }

    // Validate required colors resolved to something usable.
    if (!primary.isValid()) {
        if (errorOut)
            *errorOut = QStringLiteral("invalid color: primary");
        return false;
    }
    if (!background.isValid()) {
        if (errorOut)
            *errorOut = QStringLiteral("invalid color: background");
        return false;
    }
    if (!onSurface.isValid()) {
        if (errorOut)
            *errorOut = QStringLiteral("invalid color: on_surface");
        return false;
    }

    target->m_primary = primary;
    target->m_onPrimary = onPrimary;
    target->m_secondary = secondary;
    target->m_onSecondary = onSecondary;
    target->m_tertiary = tertiary;
    target->m_onTertiary = onTertiary;
    target->m_background = background;
    target->m_onBackground = onBackground;
    target->m_surface = surface;
    target->m_onSurface = onSurface;
    target->m_surfaceVariant = surfaceVariant;
    target->m_surfaceContainer = surfaceContainer;
    target->m_surfaceContainerHigh = surfaceContainerHigh;
    target->m_outline = outline;
    target->m_error = error;
    target->m_onError = onError;

    const QJsonValue mode = obj.value(QStringLiteral("mode"));
    target->m_mode = mode.isString() ? mode.toString() : QStringLiteral("dark");
    target->m_usingFallback = false;
    target->m_warning.clear();
    return true;
}

void PaletteManager::reload()
{
    m_palettePath = resolvePalettePath();

    QFile f(m_palettePath);
    if (m_palettePath.isEmpty() || !f.exists()) {
        const QString reason = QStringLiteral("file not found: %1").arg(
            m_palettePath.isEmpty() ? QStringLiteral("(no config path)") : m_palettePath);
        qInfo(lcPalette) << reason;
        applyFallback(reason);
        return;
    }
    if (!f.open(QIODevice::ReadOnly)) {
        const QString reason = QStringLiteral("cannot read: %1 (%2)")
                                   .arg(m_palettePath, f.errorString());
        qWarning(lcPalette) << reason;
        applyFallback(reason);
        return;
    }

    const QByteArray data = f.readAll();
    // Atomic replace race: empty/partial file — keep last good palette if any.
    if (data.trimmed().isEmpty()) {
        const QString reason = QStringLiteral("invalid JSON: empty file");
        qWarning(lcPalette) << reason << m_palettePath;
        if (!m_hadSuccessfulLoad)
            applyFallback(reason);
        else
            m_warning = reason;
        emit paletteChanged();
        return;
    }

    QString err;
    if (!parsePaletteJson(data, this, &err)) {
        qWarning(lcPalette) << "palette load failed:" << err << m_palettePath;
        if (!m_hadSuccessfulLoad)
            applyFallback(err);
        else {
            // Keep last good colors; surface the reason.
            m_warning = err;
            emit paletteChanged();
        }
        return;
    }

    m_hadSuccessfulLoad = true;
    m_usingFallback = false;
    m_warning.clear();
    qInfo(lcPalette) << "loaded palette from" << m_palettePath
                      << "primary" << m_primary.name()
                      << "on_surface" << m_onSurface.name();
    logDiagnostics(QStringLiteral("reload/success"));
    emit paletteChanged();
}

void PaletteManager::scheduleReloadFromWatcher()
{
    rearmWatcher();
    if (!m_reloadDebounce) {
        m_reloadDebounce = new QTimer(this);
        m_reloadDebounce->setSingleShot(true);
        m_reloadDebounce->setInterval(150);
        connect(m_reloadDebounce, &QTimer::timeout, this, &PaletteManager::reload);
    }
    // Coalesce inotify bursts from Matugen atomic replace (no polling loop).
    m_reloadDebounce->start();
}

void PaletteManager::rearmWatcher()
{
    if (!m_watcher)
        return;
    const QString dir = QFileInfo(m_palettePath).absolutePath();
    if (QFileInfo::exists(dir) && !m_watcher->directories().contains(dir))
        m_watcher->addPath(dir);
    if (QFileInfo::exists(m_palettePath) && !m_watcher->files().contains(m_palettePath))
        m_watcher->addPath(m_palettePath);
}

void PaletteManager::watchPaletteFile()
{
    m_watcher = new QFileSystemWatcher(this);
    rearmWatcher();

    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &) {
        scheduleReloadFromWatcher();
    });
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
        // Parent dir watch catches Matugen rename/replace of palette.json.
        scheduleReloadFromWatcher();
    });
}
