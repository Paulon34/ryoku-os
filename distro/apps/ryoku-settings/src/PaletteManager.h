#pragma once

#include <QColor>
#include <QObject>
#include <QString>

class QFileSystemWatcher;
class QTimer;

class PaletteManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QColor primary READ primary NOTIFY paletteChanged)
    Q_PROPERTY(QColor onPrimary READ onPrimary NOTIFY paletteChanged)
    Q_PROPERTY(QColor secondary READ secondary NOTIFY paletteChanged)
    Q_PROPERTY(QColor onSecondary READ onSecondary NOTIFY paletteChanged)
    Q_PROPERTY(QColor tertiary READ tertiary NOTIFY paletteChanged)
    Q_PROPERTY(QColor onTertiary READ onTertiary NOTIFY paletteChanged)
    Q_PROPERTY(QColor background READ background NOTIFY paletteChanged)
    Q_PROPERTY(QColor onBackground READ onBackground NOTIFY paletteChanged)
    Q_PROPERTY(QColor surface READ surface NOTIFY paletteChanged)
    Q_PROPERTY(QColor onSurface READ onSurface NOTIFY paletteChanged)
    Q_PROPERTY(QColor surfaceVariant READ surfaceVariant NOTIFY paletteChanged)
    Q_PROPERTY(QColor surfaceContainer READ surfaceContainer NOTIFY paletteChanged)
    Q_PROPERTY(QColor surfaceContainerHigh READ surfaceContainerHigh NOTIFY paletteChanged)
    Q_PROPERTY(QColor outline READ outline NOTIFY paletteChanged)
    Q_PROPERTY(QColor error READ error NOTIFY paletteChanged)
    Q_PROPERTY(QColor onError READ onError NOTIFY paletteChanged)
    Q_PROPERTY(QString mode READ mode NOTIFY paletteChanged)
    Q_PROPERTY(bool usingFallback READ usingFallback NOTIFY paletteChanged)
    Q_PROPERTY(QString palettePath READ palettePath NOTIFY paletteChanged)
    Q_PROPERTY(QString warning READ warning NOTIFY paletteChanged)
    Q_PROPERTY(QString fallbackReason READ warning NOTIFY paletteChanged)

public:
    explicit PaletteManager(QObject *parent = nullptr);

    QColor primary() const { return m_primary; }
    QColor onPrimary() const { return m_onPrimary; }
    QColor secondary() const { return m_secondary; }
    QColor onSecondary() const { return m_onSecondary; }
    QColor tertiary() const { return m_tertiary; }
    QColor onTertiary() const { return m_onTertiary; }
    QColor background() const { return m_background; }
    QColor onBackground() const { return m_onBackground; }
    QColor surface() const { return m_surface; }
    QColor onSurface() const { return m_onSurface; }
    QColor surfaceVariant() const { return m_surfaceVariant; }
    QColor surfaceContainer() const { return m_surfaceContainer; }
    QColor surfaceContainerHigh() const { return m_surfaceContainerHigh; }
    QColor outline() const { return m_outline; }
    QColor error() const { return m_error; }
    QColor onError() const { return m_onError; }
    QString mode() const { return m_mode; }
    bool usingFallback() const { return m_usingFallback; }
    QString palettePath() const { return m_palettePath; }
    QString warning() const { return m_warning; }

    Q_INVOKABLE void reload();

    // Pure helpers for tests.
    static bool parsePaletteJson(const QByteArray &json, PaletteManager *target, QString *errorOut);
    static QString resolvePalettePath();

signals:
    void paletteChanged();

private:
    void applyFallback(const QString &reason);
    void watchPaletteFile();
    void scheduleReloadFromWatcher();
    void rearmWatcher();
    void logDiagnostics(const QString &phase) const;

    QString m_palettePath;
    QString m_warning;
    QString m_mode = QStringLiteral("dark");
    bool m_usingFallback = true;
    bool m_hadSuccessfulLoad = false;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_reloadDebounce = nullptr;

    QColor m_primary;
    QColor m_onPrimary;
    QColor m_secondary;
    QColor m_onSecondary;
    QColor m_tertiary;
    QColor m_onTertiary;
    QColor m_background;
    QColor m_onBackground;
    QColor m_surface;
    QColor m_onSurface;
    QColor m_surfaceVariant;
    QColor m_surfaceContainer;
    QColor m_surfaceContainerHigh;
    QColor m_outline;
    QColor m_error;
    QColor m_onError;
};
