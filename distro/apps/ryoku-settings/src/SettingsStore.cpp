#include "SettingsStore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QJSValue>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTimer>
#include <algorithm>
#include <QSet>

Q_LOGGING_CATEGORY(lcSettings, "ryoku.settings.store")

namespace {

QVariant jsonToVariant(const QJsonValue &v)
{
    if (v.isNull() || v.isUndefined())
        return QVariant();
    if (v.isBool())
        return v.toBool();
    if (v.isDouble())
        return v.toDouble();
    if (v.isString())
        return v.toString();
    if (v.isObject())
        return v.toObject().toVariantMap();
    if (v.isArray())
        return v.toArray().toVariantList();
    return QVariant();
}

QVariantMap objectToMap(const QJsonObject &obj)
{
    QVariantMap map;
    for (auto it = obj.begin(); it != obj.end(); ++it)
        map.insert(it.key(), jsonToVariant(it.value()));
    return map;
}

QJsonValue variantToJson(const QVariant &v)
{
    if (!v.isValid() || v.isNull())
        return QJsonValue();
    switch (v.userType()) {
    case QMetaType::Bool:
        return v.toBool();
    case QMetaType::Int:
    case QMetaType::LongLong:
    case QMetaType::UInt:
    case QMetaType::ULongLong:
    case QMetaType::Double:
    case QMetaType::Float:
        return v.toDouble();
    case QMetaType::QString:
        return v.toString();
    default:
        if (v.canConvert<QString>())
            return v.toString();
        return QJsonValue();
    }
}

bool isPresent(const QVariant &v)
{
    return v.isValid() && !v.isNull();
}

// QML may hand a JS object over as QJSValue instead of QVariantMap.
QVariantMap toVariantMap(const QVariant &v)
{
    if (v.metaType() == QMetaType::fromType<QJSValue>())
        return v.value<QJSValue>().toVariant().toMap();
    return v.toMap();
}

const QStringList &videoWallpaperKeys()
{
    static const QStringList keys{QStringLiteral("file"), QStringLiteral("loop"),
                                  QStringLiteral("audio"), QStringLiteral("profile"),
                                  QStringLiteral("pauseWhenCovered")};
    return keys;
}

bool jsonValuesEqual(const QJsonValue &a, const QJsonValue &b)
{
    if (a.type() != b.type()) {
        // Treat undefined and null similarly for absence.
        if ((a.isNull() || a.isUndefined()) && (b.isNull() || b.isUndefined()))
            return true;
        return false;
    }
    if (a.isDouble() && b.isDouble())
        return qFuzzyCompare(a.toDouble() + 1.0, b.toDouble() + 1.0);
    return a == b;
}

} // namespace

SettingsStore::SettingsStore(QObject *parent)
    : QObject(parent)
{
}

void SettingsStore::setRepoPath(const QString &repoPath)
{
    m_repoPath = repoPath;
    reload();
    watchSettingsFile();
}

QString SettingsStore::displayValue(const QVariant &v)
{
    if (!v.isValid() || v.isNull())
        return tr("Current system value");
    return v.toString();
}

QString SettingsStore::boolDisplay(const QVariant &v)
{
    if (!v.isValid() || v.isNull())
        return tr("Current system value");
    return v.toBool() ? tr("On") : tr("Off");
}

QString SettingsStore::dynamicColorsDisplay() const { return boolDisplay(m_appearance.value(QStringLiteral("dynamicColors"))); }
QString SettingsStore::wallpaperDisplay() const
{
    if (m_appearance.value(QStringLiteral("wallpaperType")).toString() == QStringLiteral("video")) {
        const QVariant file = m_appearance.value(QStringLiteral("videoWallpaper")).toMap().value(QStringLiteral("file"));
        if (isPresent(file))
            return file.toString();
    }
    return displayValue(m_appearance.value(QStringLiteral("wallpaper")));
}
QString SettingsStore::iconThemeDisplay() const { return displayValue(m_appearance.value(QStringLiteral("iconTheme"))); }
QString SettingsStore::cursorThemeDisplay() const { return displayValue(m_appearance.value(QStringLiteral("cursorTheme"))); }
QString SettingsStore::fontUiDisplay() const { return displayValue(m_appearance.value(QStringLiteral("fontUi"))); }
QString SettingsStore::fontMonoDisplay() const { return displayValue(m_appearance.value(QStringLiteral("fontMono"))); }
QString SettingsStore::transparencyDisplay() const
{
    const QVariant v = m_appearance.value(QStringLiteral("transparency"));
    if (!v.isValid() || v.isNull())
        return tr("Current system value");
    return QString::number(v.toDouble(), 'f', 2);
}
QString SettingsStore::animationsDisplay() const { return boolDisplay(m_appearance.value(QStringLiteral("animations"))); }
QString SettingsStore::gapsInDisplay() const { return displayValue(m_hyprland.value(QStringLiteral("gapsIn"))); }
QString SettingsStore::gapsOutDisplay() const { return displayValue(m_hyprland.value(QStringLiteral("gapsOut"))); }
QString SettingsStore::roundingDisplay() const { return displayValue(m_hyprland.value(QStringLiteral("rounding"))); }

bool SettingsStore::dynamicColorsEnabled() const
{
    const QVariant v = m_appearance.value(QStringLiteral("dynamicColors"));
    return v.isValid() && !v.isNull() && v.toBool();
}

QVariant SettingsStore::wallpaperValue() const { return m_appearance.value(QStringLiteral("wallpaper")); }
QVariant SettingsStore::loginWallpaperValue() const { return m_appearance.value(QStringLiteral("loginWallpaper")); }
QVariant SettingsStore::dynamicColorsValue() const { return m_appearance.value(QStringLiteral("dynamicColors")); }
QVariant SettingsStore::animationsValue() const { return m_appearance.value(QStringLiteral("animations")); }
QVariant SettingsStore::transparencyValue() const { return m_appearance.value(QStringLiteral("transparency")); }
QVariant SettingsStore::wallpaperTypeValue() const { return m_appearance.value(QStringLiteral("wallpaperType")); }
QVariant SettingsStore::videoWallpaperValue() const { return m_appearance.value(QStringLiteral("videoWallpaper")); }
QVariant SettingsStore::visualProfileValue() const { return m_appearance.value(QStringLiteral("visualProfile")); }
QVariant SettingsStore::visualProfileAutoValue() const { return m_appearance.value(QStringLiteral("visualProfileAuto")); }
QVariant SettingsStore::shellStyleValue() const { return m_appearance.value(QStringLiteral("shellStyle")); }

bool SettingsStore::isValidVisualProfile(const QString &profile)
{
    return profile == QStringLiteral("economy") || profile == QStringLiteral("balanced")
        || profile == QStringLiteral("cinematic");
}

bool SettingsStore::mergeVisualProfileAndSerialize(const QJsonObject &rootIn,
                                                   const QVariant &profile,
                                                   const QVariant &autoMode,
                                                   QByteArray *outJson,
                                                   QString *errorOut)
{
    auto fail = [errorOut](const QString &msg) {
        if (errorOut)
            *errorOut = msg;
        return false;
    };
    if (!outJson)
        return false;
    if (rootIn.value(QStringLiteral("schemaVersion")).toInt() != 1)
        return fail(QStringLiteral("Unsupported schemaVersion (expected 1)"));
    if (isPresent(profile)
        && (profile.typeId() != QMetaType::QString || !isValidVisualProfile(profile.toString())))
        return fail(QStringLiteral("visualProfile must be null, economy, balanced or cinematic"));
    if (isPresent(autoMode) && autoMode.typeId() != QMetaType::Bool)
        return fail(QStringLiteral("visualProfileAuto must be null or bool"));

    QJsonObject root = rootIn;
    QJsonObject appearance = root.value(QStringLiteral("appearance")).toObject();
    // Same omit-when-null rule as the other optional appearance keys.
    const auto put = [&appearance](const QString &key, const QVariant &v) {
        if (isPresent(v))
            appearance.insert(key, variantToJson(v));
        else if (appearance.contains(key))
            appearance.insert(key, QJsonValue());
    };
    put(QStringLiteral("visualProfile"), profile);
    put(QStringLiteral("visualProfileAuto"), autoMode);
    root.insert(QStringLiteral("appearance"), appearance);

    *outJson = QJsonDocument(root).toJson(QJsonDocument::Indented);
    return true;
}

bool SettingsStore::saveVisualProfile(const QVariant &profile, const QVariant &autoMode)
{
    m_lastWriteError.clear();
    if (!m_loaded) {
        m_lastWriteError = QStringLiteral("Settings not loaded");
        emit writeFinished(false);
        return false;
    }

    QByteArray out;
    QString err;
    if (!mergeVisualProfileAndSerialize(m_root, profile, autoMode, &out, &err)
        || !commitSerialized(out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "visual profile save failed:" << err;
        emit writeFinished(false);
        return false;
    }

    qInfo(lcSettings) << "saved visual profile" << profile << "auto" << autoMode;
    emit writeFinished(true);
    return true;
}

bool SettingsStore::isValidShellStyle(const QString &style)
{
    return style == QStringLiteral("quattro") || style == QStringLiteral("islands");
}

bool SettingsStore::mergeShellStyleAndSerialize(const QJsonObject &rootIn,
                                                const QVariant &style,
                                                QByteArray *outJson,
                                                QString *errorOut)
{
    auto fail = [errorOut](const QString &msg) {
        if (errorOut)
            *errorOut = msg;
        return false;
    };
    if (!outJson)
        return false;
    if (rootIn.value(QStringLiteral("schemaVersion")).toInt() != 1)
        return fail(QStringLiteral("Unsupported schemaVersion (expected 1)"));
    if (isPresent(style)
        && (style.typeId() != QMetaType::QString || !isValidShellStyle(style.toString())))
        return fail(QStringLiteral("shellStyle must be null, quattro or islands"));

    QJsonObject root = rootIn;
    QJsonObject appearance = root.value(QStringLiteral("appearance")).toObject();
    if (isPresent(style))
        appearance.insert(QStringLiteral("shellStyle"), style.toString());
    else if (appearance.contains(QStringLiteral("shellStyle")))
        appearance.insert(QStringLiteral("shellStyle"), QJsonValue());
    root.insert(QStringLiteral("appearance"), appearance);

    *outJson = QJsonDocument(root).toJson(QJsonDocument::Indented);
    return true;
}

bool SettingsStore::saveShellStyle(const QVariant &style)
{
    m_lastWriteError.clear();
    if (!m_loaded) {
        m_lastWriteError = QStringLiteral("Settings not loaded");
        emit writeFinished(false);
        return false;
    }

    QByteArray out;
    QString err;
    if (!mergeShellStyleAndSerialize(m_root, style, &out, &err) || !commitSerialized(out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "shell style save failed:" << err;
        emit writeFinished(false);
        return false;
    }

    qInfo(lcSettings) << "saved shell style" << style;
    emit writeFinished(true);
    return true;
}

bool SettingsStore::isValidWallpaperId(const QString &id)
{
    static const QRegularExpression re(
        QStringLiteral(R"(^[A-Za-z0-9][A-Za-z0-9._-]*\.(jpg|jpeg|png|webp)$)"),
        QRegularExpression::CaseInsensitiveOption);
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return false;
    return re.match(id).hasMatch();
}

bool SettingsStore::isValidVideoWallpaperId(const QString &id)
{
    static const QRegularExpression re(
        QStringLiteral(R"(^[A-Za-z0-9][A-Za-z0-9._-]*\.(mp4|webm|mkv|mov)$)"),
        QRegularExpression::CaseInsensitiveOption);
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QStringLiteral("..")))
        return false;
    return re.match(id).hasMatch();
}

bool SettingsStore::validateVideoWallpaper(const QVariant &wallpaperType,
                                           const QVariant &videoWallpaper,
                                           QString *errorOut)
{
    auto fail = [errorOut](const QString &msg) {
        if (errorOut)
            *errorOut = msg;
        return false;
    };

    QString type;
    if (isPresent(wallpaperType)) {
        type = wallpaperType.toString();
        if (wallpaperType.typeId() != QMetaType::QString
            || (type != QStringLiteral("image") && type != QStringLiteral("video")))
            return fail(QStringLiteral("wallpaperType must be null, \"image\" or \"video\""));
    }

    QVariantMap video;
    if (isPresent(videoWallpaper)) {
        if (videoWallpaper.typeId() != QMetaType::QVariantMap
            && videoWallpaper.metaType() != QMetaType::fromType<QJSValue>())
            return fail(QStringLiteral("videoWallpaper must be null or an object"));
        video = toVariantMap(videoWallpaper);

        const QVariant file = video.value(QStringLiteral("file"));
        if (isPresent(file)
            && (file.typeId() != QMetaType::QString || !isValidVideoWallpaperId(file.toString())))
            return fail(QStringLiteral("invalid videoWallpaper.file"));

        for (const QString &key : {QStringLiteral("loop"), QStringLiteral("audio"),
                                   QStringLiteral("pauseWhenCovered")}) {
            const QVariant v = video.value(key);
            if (isPresent(v) && v.typeId() != QMetaType::Bool)
                return fail(QStringLiteral("videoWallpaper.%1 must be null or bool").arg(key));
        }

        const QVariant profile = video.value(QStringLiteral("profile"));
        if (isPresent(profile)) {
            const QString p = profile.toString();
            if (profile.typeId() != QMetaType::QString
                || (p != QStringLiteral("economy") && p != QStringLiteral("balanced")
                    && p != QStringLiteral("quality")))
                return fail(QStringLiteral("videoWallpaper.profile must be null, economy, balanced or quality"));
        }
    }

    if (type == QStringLiteral("video") && !isPresent(video.value(QStringLiteral("file"))))
        return fail(QStringLiteral("wallpaperType \"video\" requires videoWallpaper.file"));

    return true;
}

bool SettingsStore::isValidFlatpakId(const QString &id)
{
    // Reverse-DNS Flatpak application ID: at least two dotted segments.
    static const QRegularExpression re(
        QStringLiteral(R"(^[A-Za-z0-9][A-Za-z0-9._-]*(\.[A-Za-z0-9][A-Za-z0-9._-]*)+$)"));
    if (id.isEmpty() || id.contains(QLatin1Char('/')) || id.contains(QLatin1Char('\\'))
        || id.contains(QLatin1Char(' ')) || id.contains(QStringLiteral("..")))
        return false;
    return re.match(id).hasMatch();
}

QStringList SettingsStore::normalizeFlatpakDeclared(const QStringList &ids, QString *errorOut)
{
    QStringList out;
    QSet<QString> seen;
    for (const QString &raw : ids) {
        const QString id = raw.trimmed();
        if (id.isEmpty()) {
            if (errorOut)
                *errorOut = QStringLiteral("flatpak id must not be empty");
            return {};
        }
        if (!isValidFlatpakId(id)) {
            if (errorOut)
                *errorOut = QStringLiteral("invalid flatpak id: %1").arg(id);
            return {};
        }
        if (seen.contains(id))
            continue; // dedupe silently
        seen.insert(id);
        out.append(id);
    }
    std::sort(out.begin(), out.end());
    if (errorOut)
        errorOut->clear();
    return out;
}

bool SettingsStore::validateAppearanceValues(const QVariant &wallpaper,
                                             const QVariant &loginWallpaper,
                                             const QVariant &dynamicColors,
                                             const QVariant &animations,
                                             const QVariant &transparency,
                                             QString *errorOut)
{
    if (wallpaper.isValid() && !wallpaper.isNull()) {
        if (!wallpaper.canConvert<QString>() || !isValidWallpaperId(wallpaper.toString())) {
            if (errorOut)
                *errorOut = QStringLiteral("invalid wallpaper id");
            return false;
        }
    }

    if (loginWallpaper.isValid() && !loginWallpaper.isNull()) {
        if (!loginWallpaper.canConvert<QString>() || !isValidWallpaperId(loginWallpaper.toString())) {
            if (errorOut)
                *errorOut = QStringLiteral("invalid loginWallpaper id");
            return false;
        }
    }

    if (!dynamicColors.isValid() || dynamicColors.isNull() || !dynamicColors.canConvert<bool>()) {
        if (errorOut)
            *errorOut = QStringLiteral("dynamicColors must be bool");
        return false;
    }

    if (!animations.isValid() || animations.isNull() || !animations.canConvert<bool>()) {
        if (errorOut)
            *errorOut = QStringLiteral("animations must be bool");
        return false;
    }

    if (transparency.isValid() && !transparency.isNull()) {
        bool ok = false;
        const double t = transparency.toDouble(&ok);
        if (!ok || t < 0.0 || t > 1.0) {
            if (errorOut)
                *errorOut = QStringLiteral("transparency must be null or number in [0,1]");
            return false;
        }
    }

    return true;
}

bool SettingsStore::parseSettingsJson(const QByteArray &json, SettingsStore *target, QString *errorOut)
{
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut)
            *errorOut = err.errorString().isEmpty() ? QStringLiteral("Invalid settings JSON") : err.errorString();
        return false;
    }

    const QJsonObject root = doc.object();
    if (!root.contains(QStringLiteral("schemaVersion")) || !root.value(QStringLiteral("schemaVersion")).isDouble()) {
        if (errorOut)
            *errorOut = QStringLiteral("Missing schemaVersion");
        return false;
    }

    const int ver = root.value(QStringLiteral("schemaVersion")).toInt();
    if (ver != 1) {
        if (errorOut)
            *errorOut = QStringLiteral("Unsupported schemaVersion (expected 1)");
        return false;
    }

    target->applyDocument(root);
    return true;
}

void SettingsStore::applyDocument(const QJsonObject &root)
{
    m_root = root;
    m_schemaVersion = root.value(QStringLiteral("schemaVersion")).toInt();
    m_appearance = objectToMap(root.value(QStringLiteral("appearance")).toObject());
    const QJsonObject desktop = root.value(QStringLiteral("desktop")).toObject();
    m_hyprland = objectToMap(desktop.value(QStringLiteral("hyprland")).toObject());

    m_flatpakDeclared.clear();
    const QJsonObject apps = root.value(QStringLiteral("apps")).toObject();
    const QJsonArray arr = apps.value(QStringLiteral("flatpakDeclared")).toArray();
    for (const QJsonValue &v : arr) {
        if (v.isString())
            m_flatpakDeclared.append(v.toString());
    }
    m_flatpakDeclared.removeDuplicates();
    std::sort(m_flatpakDeclared.begin(), m_flatpakDeclared.end());

    m_displayMonitors.clear();
    const QJsonObject display = root.value(QStringLiteral("display")).toObject();
    const QJsonArray monitors = display.value(QStringLiteral("monitors")).toArray();
    for (const QJsonValue &v : monitors) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        QVariantMap row;
        row.insert(QStringLiteral("name"), o.value(QStringLiteral("name")).toString());
        row.insert(QStringLiteral("enabled"), o.value(QStringLiteral("enabled")).toBool(true));
        row.insert(QStringLiteral("width"), o.value(QStringLiteral("width")).toInt());
        row.insert(QStringLiteral("height"), o.value(QStringLiteral("height")).toInt());
        row.insert(QStringLiteral("refreshRate"), o.value(QStringLiteral("refreshRate")).toDouble());
        row.insert(QStringLiteral("scale"), o.value(QStringLiteral("scale")).toDouble(1.0));
        row.insert(QStringLiteral("x"), o.value(QStringLiteral("x")).toInt());
        row.insert(QStringLiteral("y"), o.value(QStringLiteral("y")).toInt());
        m_displayMonitors.append(row);
    }

    m_loaded = true;
    m_error.clear();
}

bool SettingsStore::mergeAppearanceAndSerialize(const QJsonObject &rootIn,
                                                const QVariant &wallpaper,
                                                const QVariant &loginWallpaper,
                                                const QVariant &dynamicColors,
                                                const QVariant &animations,
                                                const QVariant &transparency,
                                                QByteArray *outJson,
                                                QString *errorOut)
{
    return mergeAppearanceImpl(rootIn, wallpaper, loginWallpaper, dynamicColors, animations,
                               transparency, false, QVariant(), QVariant(), outJson, errorOut);
}

bool SettingsStore::mergeAppearanceAndSerialize(const QJsonObject &rootIn,
                                                const QVariant &wallpaper,
                                                const QVariant &loginWallpaper,
                                                const QVariant &dynamicColors,
                                                const QVariant &animations,
                                                const QVariant &transparency,
                                                const QVariant &wallpaperType,
                                                const QVariant &videoWallpaper,
                                                QByteArray *outJson,
                                                QString *errorOut)
{
    return mergeAppearanceImpl(rootIn, wallpaper, loginWallpaper, dynamicColors, animations,
                               transparency, true, wallpaperType, videoWallpaper, outJson, errorOut);
}

bool SettingsStore::mergeAppearanceImpl(const QJsonObject &rootIn,
                                        const QVariant &wallpaper,
                                        const QVariant &loginWallpaper,
                                        const QVariant &dynamicColors,
                                        const QVariant &animations,
                                        const QVariant &transparency,
                                        bool touchVideo,
                                        const QVariant &wallpaperType,
                                        const QVariant &videoWallpaper,
                                        QByteArray *outJson,
                                        QString *errorOut)
{
    if (!outJson)
        return false;

    if (!rootIn.contains(QStringLiteral("schemaVersion"))
        || rootIn.value(QStringLiteral("schemaVersion")).toInt() != 1) {
        if (errorOut)
            *errorOut = QStringLiteral("Unsupported schemaVersion (expected 1)");
        return false;
    }

    if (!validateAppearanceValues(wallpaper, loginWallpaper, dynamicColors, animations, transparency,
                                  errorOut))
        return false;

    if (touchVideo && !validateVideoWallpaper(wallpaperType, videoWallpaper, errorOut))
        return false;

    QJsonObject root = rootIn;
    QJsonObject appearance = root.value(QStringLiteral("appearance")).toObject();

    const QJsonValue newWallpaper = variantToJson(wallpaper);
    const QJsonValue newLoginWallpaper = variantToJson(loginWallpaper);
    const QJsonValue newDynamic = variantToJson(dynamicColors);
    const QJsonValue newAnim = variantToJson(animations);
    const QJsonValue newTrans = variantToJson(transparency);

    const QJsonValue existingLogin = appearance.value(QStringLiteral("loginWallpaper"));
    const bool loginIsNull = !loginWallpaper.isValid() || loginWallpaper.isNull();

    const bool unchanged =
        jsonValuesEqual(appearance.value(QStringLiteral("wallpaper")), newWallpaper)
        && jsonValuesEqual(existingLogin, newLoginWallpaper)
        && jsonValuesEqual(appearance.value(QStringLiteral("dynamicColors")), newDynamic)
        && jsonValuesEqual(appearance.value(QStringLiteral("animations")), newAnim)
        && jsonValuesEqual(appearance.value(QStringLiteral("transparency")), newTrans);

    appearance.insert(QStringLiteral("wallpaper"), newWallpaper);
    // Omit loginWallpaper when null and never present — avoids rewriting settings.json
    // merely to add an explicit null (desktop wallpaper stays independent).
    if (!loginIsNull)
        appearance.insert(QStringLiteral("loginWallpaper"), newLoginWallpaper);
    else if (appearance.contains(QStringLiteral("loginWallpaper")))
        appearance.insert(QStringLiteral("loginWallpaper"), QJsonValue());
    appearance.insert(QStringLiteral("dynamicColors"), newDynamic);
    appearance.insert(QStringLiteral("animations"), newAnim);
    appearance.insert(QStringLiteral("transparency"), newTrans);

    // Same omit-when-null rule as loginWallpaper: image-only users keep a file
    // without video keys.
    if (touchVideo) {
        if (isPresent(wallpaperType))
            appearance.insert(QStringLiteral("wallpaperType"), variantToJson(wallpaperType));
        else if (appearance.contains(QStringLiteral("wallpaperType")))
            appearance.insert(QStringLiteral("wallpaperType"), QJsonValue());

        if (isPresent(videoWallpaper)) {
            QJsonObject video = appearance.value(QStringLiteral("videoWallpaper")).toObject();
            const QVariantMap draft = toVariantMap(videoWallpaper);
            for (const QString &key : videoWallpaperKeys()) {
                if (draft.contains(key))
                    video.insert(key, variantToJson(draft.value(key)));
            }
            appearance.insert(QStringLiteral("videoWallpaper"), video);
        } else if (appearance.contains(QStringLiteral("videoWallpaper"))) {
            appearance.insert(QStringLiteral("videoWallpaper"), QJsonValue());
        }
    }

    root.insert(QStringLiteral("appearance"), appearance);

    const QJsonDocument doc(root);
    const QByteArray pretty = doc.toJson(QJsonDocument::Indented);
    if (unchanged) {
        // Caller may skip write; still produce canonical bytes.
        *outJson = pretty;
        return true;
    }

    *outJson = pretty;
    return true;
}

bool SettingsStore::mergeFlatpakDeclaredAndSerialize(const QJsonObject &rootIn,
                                                     const QStringList &ids,
                                                     QByteArray *outJson,
                                                     QString *errorOut)
{
    if (!outJson)
        return false;

    if (!rootIn.contains(QStringLiteral("schemaVersion"))
        || rootIn.value(QStringLiteral("schemaVersion")).toInt() != 1) {
        if (errorOut)
            *errorOut = QStringLiteral("Unsupported schemaVersion (expected 1)");
        return false;
    }

    QString normErr;
    const QStringList normalized = normalizeFlatpakDeclared(ids, &normErr);
    if (!normErr.isEmpty()) {
        if (errorOut)
            *errorOut = normErr;
        return false;
    }

    QJsonObject root = rootIn;
    QJsonObject apps = root.value(QStringLiteral("apps")).toObject();
    QJsonArray arr;
    for (const QString &id : normalized)
        arr.append(id);
    apps.insert(QStringLiteral("flatpakDeclared"), arr);
    root.insert(QStringLiteral("apps"), apps);

    *outJson = QJsonDocument(root).toJson(QJsonDocument::Indented);
    return true;
}

bool SettingsStore::validateDisplayMonitors(const QVariantList &monitors, QString *errorOut)
{
    if (monitors.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("display.monitors must not be empty");
        return false;
    }
    int enabled = 0;
    QSet<QString> names;
    for (const QVariant &v : monitors) {
        const QVariantMap m = v.toMap();
        const QString name = m.value(QStringLiteral("name")).toString().trimmed();
        if (name.isEmpty()) {
            if (errorOut)
                *errorOut = QStringLiteral("monitor name required");
            return false;
        }
        if (names.contains(name)) {
            if (errorOut)
                *errorOut = QStringLiteral("duplicate monitor name: %1").arg(name);
            return false;
        }
        names.insert(name);
        const bool isEnabled = m.value(QStringLiteral("enabled"), true).toBool();
        if (isEnabled)
            ++enabled;
        const double scale = m.value(QStringLiteral("scale"), 1.0).toDouble();
        if (scale < 0.5 || scale > 3.0) {
            if (errorOut)
                *errorOut = QStringLiteral("invalid scale for %1").arg(name);
            return false;
        }
        if (isEnabled) {
            if (m.value(QStringLiteral("width")).toInt() <= 0
                || m.value(QStringLiteral("height")).toInt() <= 0
                || m.value(QStringLiteral("refreshRate")).toDouble() <= 0.0) {
                if (errorOut)
                    *errorOut = QStringLiteral("invalid mode for %1").arg(name);
                return false;
            }
        }
    }
    if (enabled < 1) {
        if (errorOut)
            *errorOut = QStringLiteral("at least one monitor must be enabled");
        return false;
    }
    return true;
}

QVariantList SettingsStore::normalizeDisplayMonitors(const QVariantList &monitors, QString *errorOut)
{
    if (!validateDisplayMonitors(monitors, errorOut))
        return {};

    QVariantList out;
    for (const QVariant &v : monitors) {
        const QVariantMap m = v.toMap();
        QVariantMap row;
        row.insert(QStringLiteral("name"), m.value(QStringLiteral("name")).toString().trimmed());
        row.insert(QStringLiteral("enabled"), m.value(QStringLiteral("enabled"), true).toBool());
        row.insert(QStringLiteral("width"), m.value(QStringLiteral("width")).toInt());
        row.insert(QStringLiteral("height"), m.value(QStringLiteral("height")).toInt());
        row.insert(QStringLiteral("refreshRate"), m.value(QStringLiteral("refreshRate")).toDouble());
        row.insert(QStringLiteral("scale"), m.value(QStringLiteral("scale"), 1.0).toDouble());
        row.insert(QStringLiteral("x"), m.value(QStringLiteral("x")).toInt());
        row.insert(QStringLiteral("y"), m.value(QStringLiteral("y")).toInt());
        out.append(row);
    }
    if (errorOut)
        errorOut->clear();
    return out;
}

bool SettingsStore::mergeDisplayMonitorsAndSerialize(const QJsonObject &rootIn,
                                                     const QVariantList &monitors,
                                                     QByteArray *outJson,
                                                     QString *errorOut)
{
    if (!outJson)
        return false;

    if (!rootIn.contains(QStringLiteral("schemaVersion"))
        || rootIn.value(QStringLiteral("schemaVersion")).toInt() != 1) {
        if (errorOut)
            *errorOut = QStringLiteral("Unsupported schemaVersion (expected 1)");
        return false;
    }

    QString normErr;
    const QVariantList normalized = normalizeDisplayMonitors(monitors, &normErr);
    if (!normErr.isEmpty()) {
        if (errorOut)
            *errorOut = normErr;
        return false;
    }

    QJsonObject root = rootIn;
    QJsonObject display = root.value(QStringLiteral("display")).toObject();
    QJsonArray arr;
    for (const QVariant &v : normalized) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o.insert(QStringLiteral("name"), m.value(QStringLiteral("name")).toString());
        o.insert(QStringLiteral("enabled"), m.value(QStringLiteral("enabled")).toBool());
        o.insert(QStringLiteral("width"), m.value(QStringLiteral("width")).toInt());
        o.insert(QStringLiteral("height"), m.value(QStringLiteral("height")).toInt());
        o.insert(QStringLiteral("refreshRate"), m.value(QStringLiteral("refreshRate")).toDouble());
        o.insert(QStringLiteral("scale"), m.value(QStringLiteral("scale")).toDouble());
        o.insert(QStringLiteral("x"), m.value(QStringLiteral("x")).toInt());
        o.insert(QStringLiteral("y"), m.value(QStringLiteral("y")).toInt());
        arr.append(o);
    }
    display.insert(QStringLiteral("monitors"), arr);
    root.insert(QStringLiteral("display"), display);

    *outJson = QJsonDocument(root).toJson(QJsonDocument::Indented);
    return true;
}

bool SettingsStore::writeDocument(const QJsonObject &root, QString *errorOut)
{
    return writeBytes(QJsonDocument(root).toJson(QJsonDocument::Indented), errorOut);
}

bool SettingsStore::writeBytes(const QByteArray &data, QString *errorOut)
{
    if (m_settingsPath.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("settings path empty");
        return false;
    }

    QSaveFile file(m_settingsPath);
    if (!file.open(QIODevice::WriteOnly)) {
        if (errorOut)
            *errorOut = QStringLiteral("Cannot open settings for write: %1").arg(file.errorString());
        return false;
    }

    if (file.write(data) != data.size()) {
        if (errorOut)
            *errorOut = QStringLiteral("Short write to settings.json");
        file.cancelWriting();
        return false;
    }

    m_writing = true;
    if (!file.commit()) {
        m_writing = false;
        if (errorOut)
            *errorOut = QStringLiteral("Failed to commit settings.json: %1").arg(file.errorString());
        return false;
    }
    m_writing = false;
    return true;
}

bool SettingsStore::commitSerialized(const QByteArray &out, QString *errorOut)
{
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(out, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut)
            *errorOut = QStringLiteral("Internal serialize error");
        return false;
    }

    QFile existing(m_settingsPath);
    if (existing.open(QIODevice::ReadOnly)) {
        const QByteArray onDisk = existing.readAll();
        existing.close();
        if (onDisk == out) {
            qInfo(lcSettings) << "save skipped (byte-identical to disk)";
            return true;
        }
    }

    if (!writeBytes(out, errorOut))
        return false;

    applyDocument(doc.object());
    emit changed();
    return true;
}

bool SettingsStore::saveAppearance(const QVariant &wallpaper,
                                   const QVariant &loginWallpaper,
                                   const QVariant &dynamicColors,
                                   const QVariant &animations,
                                   const QVariant &transparency)
{
    return saveAppearanceImpl(wallpaper, loginWallpaper, dynamicColors, animations, transparency,
                              false, QVariant(), QVariant());
}

bool SettingsStore::saveAppearanceWithVideo(const QVariant &wallpaper,
                                            const QVariant &loginWallpaper,
                                            const QVariant &dynamicColors,
                                            const QVariant &animations,
                                            const QVariant &transparency,
                                            const QVariant &wallpaperType,
                                            const QVariant &videoWallpaper)
{
    return saveAppearanceImpl(wallpaper, loginWallpaper, dynamicColors, animations, transparency,
                              true, wallpaperType, videoWallpaper);
}

bool SettingsStore::saveAppearanceImpl(const QVariant &wallpaper,
                                       const QVariant &loginWallpaper,
                                       const QVariant &dynamicColors,
                                       const QVariant &animations,
                                       const QVariant &transparency,
                                       bool touchVideo,
                                       const QVariant &wallpaperType,
                                       const QVariant &videoWallpaper)
{
    m_lastWriteError.clear();

    if (!m_loaded) {
        m_lastWriteError = QStringLiteral("Settings not loaded");
        emit writeFinished(false);
        return false;
    }

    QByteArray out;
    QString err;
    if (!mergeAppearanceImpl(m_root, wallpaper, loginWallpaper, dynamicColors, animations,
                             transparency, touchVideo, wallpaperType, videoWallpaper, &out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "save rejected:" << err;
        emit writeFinished(false);
        return false;
    }

    if (!commitSerialized(out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "save failed:" << err;
        emit writeFinished(false);
        return false;
    }

    qInfo(lcSettings) << "saved appearance to" << m_settingsPath;
    emit writeFinished(true);
    return true;
}

bool SettingsStore::saveFlatpakDeclared(const QStringList &ids)
{
    m_lastWriteError.clear();

    if (!m_loaded) {
        m_lastWriteError = QStringLiteral("Settings not loaded");
        emit writeFinished(false);
        return false;
    }

    QByteArray out;
    QString err;
    if (!mergeFlatpakDeclaredAndSerialize(m_root, ids, &out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "flatpak save rejected:" << err;
        emit writeFinished(false);
        return false;
    }

    if (!commitSerialized(out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "flatpak save failed:" << err;
        emit writeFinished(false);
        return false;
    }

    qInfo(lcSettings) << "saved flatpakDeclared (" << m_flatpakDeclared.size() << ") to" << m_settingsPath;
    emit writeFinished(true);
    return true;
}

bool SettingsStore::saveDisplayMonitors(const QVariantList &monitors)
{
    m_lastWriteError.clear();

    if (!m_loaded) {
        m_lastWriteError = QStringLiteral("Settings not loaded");
        emit writeFinished(false);
        return false;
    }

    QByteArray out;
    QString err;
    if (!mergeDisplayMonitorsAndSerialize(m_root, monitors, &out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "display save rejected:" << err;
        emit writeFinished(false);
        return false;
    }

    if (!commitSerialized(out, &err)) {
        m_lastWriteError = err;
        qWarning(lcSettings) << "display save failed:" << err;
        emit writeFinished(false);
        return false;
    }

    qInfo(lcSettings) << "saved display.monitors (" << m_displayMonitors.size() << ") to" << m_settingsPath;
    emit writeFinished(true);
    return true;
}

void SettingsStore::retranslateUi()
{
    emit changed();
}

void SettingsStore::reload()
{
    m_loaded = false;
    m_error.clear();
    m_schemaVersion = 0;
    m_appearance.clear();
    m_hyprland.clear();
    m_flatpakDeclared.clear();
    m_displayMonitors.clear();
    m_settingsPath.clear();
    m_root = QJsonObject();

    if (m_repoPath.isEmpty()) {
        m_error = QStringLiteral("Ryoku repository path not found");
        emit changed();
        return;
    }

    {
        const QStringList candidates{
            QDir(m_repoPath).filePath(QStringLiteral("ryoku/settings.json")),
            QDir(m_repoPath).filePath(QStringLiteral("distro/ryoku/settings.json")),
        };
        m_settingsPath.clear();
        for (const QString &c : candidates) {
            if (QFileInfo::exists(c)) {
                m_settingsPath = c;
                break;
            }
        }
    }
    QFile f(m_settingsPath);
    if (m_settingsPath.isEmpty() || !f.exists()) {
        m_error = QStringLiteral("settings.json not found");
        qWarning(lcSettings) << m_error << m_repoPath;
        emit changed();
        return;
    }
    if (!f.open(QIODevice::ReadOnly)) {
        m_error = QStringLiteral("Cannot read settings.json");
        qWarning(lcSettings) << m_error << f.errorString();
        emit changed();
        return;
    }

    QString err;
    if (!parseSettingsJson(f.readAll(), this, &err)) {
        m_error = err;
        m_loaded = false;
        qWarning(lcSettings) << "settings parse failed:" << err;
        emit changed();
        return;
    }

    qInfo(lcSettings) << "loaded settings schemaVersion" << m_schemaVersion << "from" << m_settingsPath;
    emit changed();
}

void SettingsStore::acknowledgeExternalChange()
{
    m_externalChangePending = false;
    emit externalChangePendingChanged();
    reload();
}

void SettingsStore::dismissExternalChange()
{
    m_externalChangePending = false;
    emit externalChangePendingChanged();
}

void SettingsStore::scheduleExternalReload()
{
    if (m_writing)
        return;
    if (!m_reloadDebounce) {
        m_reloadDebounce = new QTimer(this);
        m_reloadDebounce->setSingleShot(true);
        m_reloadDebounce->setInterval(150);
        connect(m_reloadDebounce, &QTimer::timeout, this, [this]() {
            if (m_writing)
                return;
            // Signal UI; do not silently overwrite a Modified draft.
            if (!m_externalChangePending) {
                m_externalChangePending = true;
                emit externalChangePendingChanged();
            }
            // If UI is Clean it should call acknowledgeExternalChange → reload.
        });
    }
    m_reloadDebounce->start();
}

void SettingsStore::watchSettingsFile()
{
    if (m_settingsPath.isEmpty())
        return;
    if (!m_watcher) {
        m_watcher = new QFileSystemWatcher(this);
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &) {
            if (QFileInfo::exists(m_settingsPath) && !m_watcher->files().contains(m_settingsPath))
                m_watcher->addPath(m_settingsPath);
            scheduleExternalReload();
        });
        connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
            if (QFileInfo::exists(m_settingsPath) && !m_watcher->files().contains(m_settingsPath))
                m_watcher->addPath(m_settingsPath);
            scheduleExternalReload();
        });
    }

    const QString dir = QFileInfo(m_settingsPath).absolutePath();
    if (QFileInfo::exists(dir) && !m_watcher->directories().contains(dir))
        m_watcher->addPath(dir);
    if (QFileInfo::exists(m_settingsPath) && !m_watcher->files().contains(m_settingsPath))
        m_watcher->addPath(m_settingsPath);
}
