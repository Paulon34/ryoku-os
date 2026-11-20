#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>
#include <QVariantList>
#include <QJsonObject>

class QFileSystemWatcher;
class QTimer;

// Read + write for ryoku/settings.json (Phase 7C/7D).
// Preserves unknown keys via full-document round-trip.
class SettingsStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loaded READ loaded NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString settingsPath READ settingsPath NOTIFY changed)
    Q_PROPERTY(int schemaVersion READ schemaVersion NOTIFY changed)

    Q_PROPERTY(QString dynamicColors READ dynamicColorsDisplay NOTIFY changed)
    Q_PROPERTY(QString wallpaper READ wallpaperDisplay NOTIFY changed)
    Q_PROPERTY(QString iconTheme READ iconThemeDisplay NOTIFY changed)
    Q_PROPERTY(QString cursorTheme READ cursorThemeDisplay NOTIFY changed)
    Q_PROPERTY(QString fontUi READ fontUiDisplay NOTIFY changed)
    Q_PROPERTY(QString fontMono READ fontMonoDisplay NOTIFY changed)
    Q_PROPERTY(QString transparency READ transparencyDisplay NOTIFY changed)
    Q_PROPERTY(QString animations READ animationsDisplay NOTIFY changed)
    Q_PROPERTY(QString gapsIn READ gapsInDisplay NOTIFY changed)
    Q_PROPERTY(QString gapsOut READ gapsOutDisplay NOTIFY changed)
    Q_PROPERTY(QString rounding READ roundingDisplay NOTIFY changed)
    Q_PROPERTY(bool dynamicColorsEnabled READ dynamicColorsEnabled NOTIFY changed)

    // Typed values for Appearance draft seeding (null → invalid QVariant).
    Q_PROPERTY(QVariant wallpaperValue READ wallpaperValue NOTIFY changed)
    Q_PROPERTY(QVariant loginWallpaperValue READ loginWallpaperValue NOTIFY changed)
    Q_PROPERTY(QVariant dynamicColorsValue READ dynamicColorsValue NOTIFY changed)
    Q_PROPERTY(QVariant animationsValue READ animationsValue NOTIFY changed)
    Q_PROPERTY(QVariant transparencyValue READ transparencyValue NOTIFY changed)
    // null → "image"; videoWallpaper is an object (file/loop/audio/profile/pauseWhenCovered) or null.
    Q_PROPERTY(QVariant wallpaperTypeValue READ wallpaperTypeValue NOTIFY changed)
    Q_PROPERTY(QVariant videoWallpaperValue READ videoWallpaperValue NOTIFY changed)
    // null → "balanced" / AUTO off. Read live by DMS (RyokuVisual).
    Q_PROPERTY(QVariant visualProfileValue READ visualProfileValue NOTIFY changed)
    Q_PROPERTY(QVariant visualProfileAutoValue READ visualProfileAutoValue NOTIFY changed)
    // null → "quattro". Projected by Nix (DMS build + bar layout): needs Apply.
    Q_PROPERTY(QVariant shellStyleValue READ shellStyleValue NOTIFY changed)

    // Apps (Phase 7D) — alphabetical unique Flatpak application IDs.
    Q_PROPERTY(QStringList flatpakDeclared READ flatpakDeclared NOTIFY changed)
    Q_PROPERTY(int flatpakDeclaredCount READ flatpakDeclaredCount NOTIFY changed)

    // Display (Phase 7F) — persisted monitor layout for future Apply.
    Q_PROPERTY(QVariantList displayMonitors READ displayMonitors NOTIFY changed)
    Q_PROPERTY(bool hasDisplayMonitors READ hasDisplayMonitors NOTIFY changed)

    Q_PROPERTY(bool externalChangePending READ externalChangePending NOTIFY externalChangePendingChanged)
    Q_PROPERTY(QString lastWriteError READ lastWriteError NOTIFY writeFinished)

public:
    explicit SettingsStore(QObject *parent = nullptr);

    void setRepoPath(const QString &repoPath);
    Q_INVOKABLE void reload();
    Q_INVOKABLE void retranslateUi();

    bool loaded() const { return m_loaded; }
    QString error() const { return m_error; }
    QString settingsPath() const { return m_settingsPath; }
    int schemaVersion() const { return m_schemaVersion; }

    QString dynamicColorsDisplay() const;
    QString wallpaperDisplay() const;
    QString iconThemeDisplay() const;
    QString cursorThemeDisplay() const;
    QString fontUiDisplay() const;
    QString fontMonoDisplay() const;
    QString transparencyDisplay() const;
    QString animationsDisplay() const;
    QString gapsInDisplay() const;
    QString gapsOutDisplay() const;
    QString roundingDisplay() const;
    bool dynamicColorsEnabled() const;

    QVariant wallpaperValue() const;
    QVariant loginWallpaperValue() const;
    QVariant dynamicColorsValue() const;
    QVariant animationsValue() const;
    QVariant transparencyValue() const;
    QVariant wallpaperTypeValue() const;
    QVariant videoWallpaperValue() const;
    QVariant visualProfileValue() const;
    QVariant visualProfileAutoValue() const;
    QVariant shellStyleValue() const;

    QStringList flatpakDeclared() const { return m_flatpakDeclared; }
    int flatpakDeclaredCount() const { return m_flatpakDeclared.size(); }

    QVariantList displayMonitors() const { return m_displayMonitors; }
    bool hasDisplayMonitors() const { return !m_displayMonitors.isEmpty(); }

    bool externalChangePending() const { return m_externalChangePending; }
    QString lastWriteError() const { return m_lastWriteError; }

    // Persist appearance fields. Null QVariant → JSON null for nullable keys.
    // Returns false on validation/IO error (see lastWriteError).
    // loginWallpaper is Nix-consumed (SDDM); wallpaper remains live/desktop-only.
    Q_INVOKABLE bool saveAppearance(const QVariant &wallpaper,
                                    const QVariant &loginWallpaper,
                                    const QVariant &dynamicColors,
                                    const QVariant &animations,
                                    const QVariant &transparency);

    // saveAppearance + appearance.wallpaperType / appearance.videoWallpaper (live, not Nix-projected).
    // Unknown keys inside videoWallpaper are preserved.
    Q_INVOKABLE bool saveAppearanceWithVideo(const QVariant &wallpaper,
                                             const QVariant &loginWallpaper,
                                             const QVariant &dynamicColors,
                                             const QVariant &animations,
                                             const QVariant &transparency,
                                             const QVariant &wallpaperType,
                                             const QVariant &videoWallpaper);

    // Persist appearance.visualProfile / visualProfileAuto immediately (live in
    // DMS, not part of the page draft). Only these two keys are touched.
    Q_INVOKABLE bool saveVisualProfile(const QVariant &profile, const QVariant &autoMode);

    // Persist appearance.shellStyle immediately; the change reaches the
    // desktop through Apply (it is part of the Nix apply subset).
    Q_INVOKABLE bool saveShellStyle(const QVariant &style);

    // Persist apps.flatpakDeclared (sorted unique IDs).
    Q_INVOKABLE bool saveFlatpakDeclared(const QStringList &ids);

    // Persist display.monitors (Phase 7F — JSON only, no HM projection yet).
    Q_INVOKABLE bool saveDisplayMonitors(const QVariantList &monitors);

    Q_INVOKABLE void acknowledgeExternalChange(); // reload after external edit
    Q_INVOKABLE void dismissExternalChange();     // keep draft; clear flag only

    // Pure helpers / tests.
    static bool parseSettingsJson(const QByteArray &json, SettingsStore *target, QString *errorOut);
    static bool mergeAppearanceAndSerialize(const QJsonObject &rootIn,
                                            const QVariant &wallpaper,
                                            const QVariant &loginWallpaper,
                                            const QVariant &dynamicColors,
                                            const QVariant &animations,
                                            const QVariant &transparency,
                                            QByteArray *outJson,
                                            QString *errorOut);
    static bool mergeAppearanceAndSerialize(const QJsonObject &rootIn,
                                            const QVariant &wallpaper,
                                            const QVariant &loginWallpaper,
                                            const QVariant &dynamicColors,
                                            const QVariant &animations,
                                            const QVariant &transparency,
                                            const QVariant &wallpaperType,
                                            const QVariant &videoWallpaper,
                                            QByteArray *outJson,
                                            QString *errorOut);
    static bool mergeVisualProfileAndSerialize(const QJsonObject &rootIn,
                                               const QVariant &profile,
                                               const QVariant &autoMode,
                                               QByteArray *outJson,
                                               QString *errorOut);
    static bool isValidVisualProfile(const QString &profile);
    static bool mergeShellStyleAndSerialize(const QJsonObject &rootIn,
                                            const QVariant &style,
                                            QByteArray *outJson,
                                            QString *errorOut);
    static bool isValidShellStyle(const QString &style);
    static bool mergeFlatpakDeclaredAndSerialize(const QJsonObject &rootIn,
                                                 const QStringList &ids,
                                                 QByteArray *outJson,
                                                 QString *errorOut);
    static bool mergeDisplayMonitorsAndSerialize(const QJsonObject &rootIn,
                                                 const QVariantList &monitors,
                                                 QByteArray *outJson,
                                                 QString *errorOut);
    static bool isValidWallpaperId(const QString &id);
    static bool isValidVideoWallpaperId(const QString &id);
    static bool validateVideoWallpaper(const QVariant &wallpaperType,
                                       const QVariant &videoWallpaper,
                                       QString *errorOut);
    static bool isValidFlatpakId(const QString &id);
    static QStringList normalizeFlatpakDeclared(const QStringList &ids, QString *errorOut);
    static bool validateAppearanceValues(const QVariant &wallpaper,
                                         const QVariant &loginWallpaper,
                                         const QVariant &dynamicColors,
                                         const QVariant &animations,
                                         const QVariant &transparency,
                                         QString *errorOut);
    static bool validateDisplayMonitors(const QVariantList &monitors, QString *errorOut);
    static QVariantList normalizeDisplayMonitors(const QVariantList &monitors, QString *errorOut);

signals:
    void changed();
    void externalChangePendingChanged();
    void writeFinished(bool ok);

private:
    void watchSettingsFile();
    void scheduleExternalReload();
    void applyDocument(const QJsonObject &root);
    bool writeDocument(const QJsonObject &root, QString *errorOut);
    bool writeBytes(const QByteArray &data, QString *errorOut);
    bool commitSerialized(const QByteArray &out, QString *errorOut);

    static QString displayValue(const QVariant &v);
    static QString boolDisplay(const QVariant &v);
    static bool mergeAppearanceImpl(const QJsonObject &rootIn,
                                    const QVariant &wallpaper,
                                    const QVariant &loginWallpaper,
                                    const QVariant &dynamicColors,
                                    const QVariant &animations,
                                    const QVariant &transparency,
                                    bool touchVideo,
                                    const QVariant &wallpaperType,
                                    const QVariant &videoWallpaper,
                                    QByteArray *outJson,
                                    QString *errorOut);
    bool saveAppearanceImpl(const QVariant &wallpaper,
                            const QVariant &loginWallpaper,
                            const QVariant &dynamicColors,
                            const QVariant &animations,
                            const QVariant &transparency,
                            bool touchVideo,
                            const QVariant &wallpaperType,
                            const QVariant &videoWallpaper);

    QString m_repoPath;
    QString m_settingsPath;
    QString m_error;
    QString m_lastWriteError;
    bool m_loaded = false;
    int m_schemaVersion = 0;
    QVariantMap m_appearance;
    QVariantMap m_hyprland;
    QStringList m_flatpakDeclared;
    QVariantList m_displayMonitors;
    QJsonObject m_root; // full document — preserves unknown keys

    bool m_externalChangePending = false;
    bool m_writing = false;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_reloadDebounce = nullptr;
};
