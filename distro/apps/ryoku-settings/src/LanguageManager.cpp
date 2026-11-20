#include "LanguageManager.h"

#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QQmlEngine>
#include <QSettings>
#include <QVariantList>
#include <QVariantMap>

LanguageManager::LanguageManager(QObject *parent)
    : QObject(parent)
{
    loadPersisted();
    m_effectiveLocale = resolveEffectiveLocale(m_language);
}

void LanguageManager::setEngine(QQmlEngine *engine)
{
    m_engine = engine;
    applyTranslator();
}

QString LanguageManager::settingsOrg()
{
    return QStringLiteral("org.ryoku");
}

QString LanguageManager::settingsApp()
{
    return QStringLiteral("RyokuSettings");
}

QString LanguageManager::settingsKey()
{
    return QStringLiteral("ui/language");
}

QString LanguageManager::normalizeSelector(const QString &raw)
{
    const QString s = raw.trimmed();
    if (s == QLatin1String("pt_BR") || s == QLatin1String("pt-BR") || s == QLatin1String("pt"))
        return QStringLiteral("pt_BR");
    if (s == QLatin1String("en") || s == QLatin1String("en_US") || s == QLatin1String("en-US"))
        return QStringLiteral("en");
    if (s == QLatin1String("system") || s.isEmpty())
        return QStringLiteral("system");
    return QStringLiteral("system");
}

QString LanguageManager::resolveEffectiveLocale(const QString &selector)
{
    const QString sel = normalizeSelector(selector);
    if (sel == QLatin1String("pt_BR"))
        return QStringLiteral("pt_BR");
    if (sel == QLatin1String("en"))
        return QStringLiteral("en");

    // system → Portuguese family uses pt_BR; everything else falls back to English.
    const QString sysName = QLocale::system().name(); // e.g. pt_BR
    if (sysName.startsWith(QLatin1String("pt")))
        return QStringLiteral("pt_BR");
    return QStringLiteral("en");
}

void LanguageManager::loadPersisted()
{
    QSettings settings(settingsOrg(), settingsApp());
    m_language = normalizeSelector(settings.value(settingsKey(), QStringLiteral("system")).toString());
}

void LanguageManager::persist() const
{
    QSettings settings(settingsOrg(), settingsApp());
    settings.setValue(settingsKey(), m_language);
    settings.sync();
}

void LanguageManager::setLanguage(const QString &language)
{
    const QString next = normalizeSelector(language);
    if (next != m_language) {
        m_language = next;
        persist();
    } else {
        m_language = next;
    }
    applyTranslator();
}

QString LanguageManager::displayName() const
{
    if (m_language == QLatin1String("pt_BR"))
        return QStringLiteral("Português (Brasil)");
    if (m_language == QLatin1String("en"))
        return QStringLiteral("English");
    return QCoreApplication::translate("LanguageManager", "Automatic (System)");
}

QVariantList LanguageManager::languageOptions() const
{
    // Language names stay recognizable in their own language (spec §7).
    QVariantList out;
    auto add = [&](const QString &id, const QString &label) {
        QVariantMap m;
        m.insert(QStringLiteral("id"), id);
        m.insert(QStringLiteral("label"), label);
        out.append(m);
    };
    add(QStringLiteral("system"),
        QCoreApplication::translate("LanguageManager", "Automatic (System)"));
    add(QStringLiteral("pt_BR"), QStringLiteral("Português (Brasil)"));
    add(QStringLiteral("en"), QStringLiteral("English"));
    return out;
}

void LanguageManager::removeTranslator()
{
    if (!m_translatorInstalled)
        return;
    QCoreApplication::removeTranslator(&m_translator);
    m_translatorInstalled = false;
}

bool LanguageManager::installTranslation(const QString &locale)
{
    removeTranslator();
    if (locale == QLatin1String("en"))
        return true; // source language — no translator

    // Prefer embedded resource; fall back to adjacent share path.
    const QStringList candidates = {
        QStringLiteral(":/i18n/ryoku-settings_%1.qm").arg(locale),
        QCoreApplication::applicationDirPath()
            + QStringLiteral("/../share/ryoku-settings/translations/ryoku-settings_%1.qm").arg(locale),
        QStringLiteral("/run/current-system/sw/share/ryoku-settings/translations/ryoku-settings_%1.qm")
            .arg(locale),
    };

    for (const QString &path : candidates) {
        if (!QFile::exists(path) && !path.startsWith(QLatin1String(":/")))
            continue;
        if (m_translator.load(path)) {
            QCoreApplication::installTranslator(&m_translator);
            m_translatorInstalled = true;
            return true;
        }
        // QTranslator::load for :/ may need load(filename, directory)
        if (path.startsWith(QLatin1String(":/"))) {
            const QFileInfo fi(path);
            if (m_translator.load(fi.fileName(), fi.path())) {
                QCoreApplication::installTranslator(&m_translator);
                m_translatorInstalled = true;
                return true;
            }
        }
    }
    return false;
}

void LanguageManager::applyTranslator()
{
    m_effectiveLocale = resolveEffectiveLocale(m_language);

    const bool ok = installTranslation(m_effectiveLocale);
    if (!ok && m_effectiveLocale == QLatin1String("pt_BR")) {
        // Missing qm → fall back to English presentation.
        m_effectiveLocale = QStringLiteral("en");
        removeTranslator();
    }

    if (m_engine)
        m_engine->retranslate();

    emit languageChanged();
}
