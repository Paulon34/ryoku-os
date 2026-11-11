#pragma once

#include <QObject>
#include <QString>
#include <QTranslator>

class QQmlEngine;

// Local UI language preference — NOT part of ryoku/settings.json / Apply.
// Selectors: "system" | "pt_BR" | "en"
class LanguageManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString effectiveLocale READ effectiveLocale NOTIFY languageChanged)
    Q_PROPERTY(QString displayName READ displayName NOTIFY languageChanged)

public:
    explicit LanguageManager(QObject *parent = nullptr);

    void setEngine(QQmlEngine *engine);

    QString language() const { return m_language; }
    void setLanguage(const QString &language);

    QString effectiveLocale() const { return m_effectiveLocale; }
    QString displayName() const;

    Q_INVOKABLE QVariantList languageOptions() const;

    // Pure helpers (tests).
    static QString normalizeSelector(const QString &raw);
    static QString resolveEffectiveLocale(const QString &selector);
    static QString settingsKey();
    static QString settingsOrg();
    static QString settingsApp();

signals:
    void languageChanged();

private:
    void loadPersisted();
    void persist() const;
    void applyTranslator();
    bool installTranslation(const QString &locale);
    void removeTranslator();

    QQmlEngine *m_engine = nullptr;
    QTranslator m_translator;
    bool m_translatorInstalled = false;
    QString m_language = QStringLiteral("system");
    QString m_effectiveLocale = QStringLiteral("en");
};
