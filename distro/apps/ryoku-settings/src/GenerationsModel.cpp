#include "GenerationsModel.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <algorithm>

Q_LOGGING_CATEGORY(lcGenerations, "ryoku.settings.generations")

GenerationsModel::GenerationsModel(QObject *parent)
    : QObject(parent)
{
}

GenerationsModel::~GenerationsModel()
{
    if (m_process) {
        m_process->kill();
        m_process->waitForFinished(500);
    }
}

void GenerationsModel::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
}

int GenerationsModel::parseProfileGenerationFromSymlinkTarget(const QString &targetOrName)
{
    // Prefer Home Manager (Debian Modular); also accept NixOS system-* for shared tests.
    static const QRegularExpression reHm(QStringLiteral("(?:^|/)home-manager-(\\d+)-link$"));
    static const QRegularExpression reSys(QStringLiteral("(?:^|/)system-(\\d+)-link$"));
    auto m = reHm.match(targetOrName);
    if (!m.hasMatch())
        m = reSys.match(targetOrName);
    if (!m.hasMatch())
        return -1;
    bool ok = false;
    const int gen = m.captured(1).toInt(&ok);
    return ok ? gen : -1;
}

QVariantList GenerationsModel::parseListGenerationsJson(const QByteArray &json, int limit,
                                                        int *currentOut, QString *errorOut)
{
    if (currentOut)
        *currentOut = -1;
    if (errorOut)
        errorOut->clear();

    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isArray()) {
        if (errorOut)
            *errorOut = pe.error != QJsonParseError::NoError
                            ? pe.errorString()
                            : QStringLiteral("Expected JSON array");
        return {};
    }

    struct Row {
        int generation = -1;
        QVariantMap map;
    };
    QList<Row> rows;
    const QJsonArray arr = doc.array();
    for (const QJsonValue &v : arr) {
        if (!v.isObject())
            continue;
        const QJsonObject o = v.toObject();
        Row r;
        r.generation = o.value(QStringLiteral("generation")).toInt(-1);
        if (r.generation < 0)
            continue;
        r.map.insert(QStringLiteral("generation"), r.generation);
        r.map.insert(QStringLiteral("date"), o.value(QStringLiteral("date")).toString());
        r.map.insert(QStringLiteral("nixosVersion"), o.value(QStringLiteral("nixosVersion")).toString());
        r.map.insert(QStringLiteral("kernelVersion"), o.value(QStringLiteral("kernelVersion")).toString());
        const QString cfgRev = o.value(QStringLiteral("configurationRevision")).toString();
        r.map.insert(QStringLiteral("configurationRevision"), cfgRev);
        const bool current = o.value(QStringLiteral("current")).toBool(false);
        r.map.insert(QStringLiteral("current"), current);
        if (current && currentOut)
            *currentOut = r.generation;
        rows.append(r);
    }

    std::sort(rows.begin(), rows.end(),
              [](const Row &a, const Row &b) { return a.generation > b.generation; });

    QVariantList out;
    const int n = limit > 0 ? qMin(limit, rows.size()) : rows.size();
    for (int i = 0; i < n; ++i)
        out.append(rows.at(i).map);
    return out;
}

void GenerationsModel::refresh()
{
    setBusy(true);
    m_error.clear();
    m_details.clear();
    emit changed();

    // Debian Modular preferred path: list per-user home-manager-*-link profiles.
    const QString user = qEnvironmentVariable("USER");
    const QString hmDir = QStringLiteral("/nix/var/nix/profiles/per-user/%1").arg(user);
    QDir dir(hmDir);
    if (!user.isEmpty() && dir.exists()) {
        static const QRegularExpression re(QStringLiteral("^home-manager-(\\d+)-link$"));
        QVariantList rows;
        int current = -1;
        const QFileInfo profileFi(hmDir + QStringLiteral("/home-manager"));
        m_profileGeneration = parseProfileGenerationFromSymlinkTarget(profileFi.symLinkTarget());
        current = m_profileGeneration;

        const QStringList names = dir.entryList(QStringList{QStringLiteral("home-manager-*-link")},
                                                QDir::Files | QDir::System | QDir::NoDotAndDotDot);
        for (const QString &name : names) {
            const auto m = re.match(name);
            if (!m.hasMatch())
                continue;
            bool ok = false;
            const int gen = m.captured(1).toInt(&ok);
            if (!ok || gen < 1)
                continue;
            QVariantMap row;
            row.insert(QStringLiteral("generation"), gen);
            row.insert(QStringLiteral("date"), QString());
            row.insert(QStringLiteral("nixosVersion"), QStringLiteral("home-manager"));
            row.insert(QStringLiteral("kernelVersion"), QString());
            row.insert(QStringLiteral("configurationRevision"), QString());
            const bool isCurrent = (gen == current);
            row.insert(QStringLiteral("current"), isCurrent);
            row.insert(QStringLiteral("isProfile"), isCurrent);
            row.insert(QStringLiteral("relationLabel"),
                       isCurrent ? QCoreApplication::translate("GenerationsModel", "Current · HM profile")
                                 : QString());
            rows.append(row);
        }
        std::sort(rows.begin(), rows.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("generation")).toInt()
                > b.toMap().value(QStringLiteral("generation")).toInt();
        });
        if (displayLimit() > 0 && rows.size() > displayLimit())
            rows = rows.mid(0, displayLimit());

        m_generations = rows;
        m_currentGeneration = current;
        m_available = !rows.isEmpty();
        if (!m_available)
            m_error = QStringLiteral("No Home Manager generations found");
        setBusy(false);
        emit changed();
        return;
    }

    // NixOS fallback: nixos-rebuild list-generations --json
    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &GenerationsModel::onFinished);
    }
    if (m_process->state() != QProcess::NotRunning)
        return;

    m_process->setProgram(QStringLiteral("nixos-rebuild"));
    m_process->setArguments({QStringLiteral("list-generations"), QStringLiteral("--json")});
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->start();
}

void GenerationsModel::onFinished(int exitCode, QProcess::ExitStatus status)
{
    setBusy(false);
    if (!m_process)
        return;
    const QByteArray out = m_process->readAllStandardOutput();
    const QByteArray err = m_process->readAllStandardError();
    m_details = QString::fromUtf8(err).trimmed().left(2000);

    if (status != QProcess::NormalExit || exitCode != 0) {
        m_available = false;
        m_error = QStringLiteral("Could not list generations");
        qWarning(lcGenerations) << "list-generations failed" << exitCode << m_details;
        emit changed();
        return;
    }

    QString parseErr;
    int current = -1;
    const QVariantList parsed =
        parseListGenerationsJson(out, displayLimit(), &current, &parseErr);
    if (!parseErr.isEmpty()) {
        m_available = false;
        m_error = parseErr;
        m_generations.clear();
        m_currentGeneration = -1;
        emit changed();
        return;
    }

    const QFileInfo profileFi(QStringLiteral("/nix/var/nix/profiles/system"));
    m_profileGeneration = parseProfileGenerationFromSymlinkTarget(profileFi.symLinkTarget());

    // Annotate profile relationship without inventing missing fields.
    QVariantList annotated;
    for (const QVariant &v : parsed) {
        QVariantMap m = v.toMap();
        const int gen = m.value(QStringLiteral("generation")).toInt();
        const bool isCurrent = m.value(QStringLiteral("current")).toBool();
        const bool isProfile = (m_profileGeneration > 0 && gen == m_profileGeneration);
        m.insert(QStringLiteral("isProfile"), isProfile);
        QString relation;
        if (isCurrent && isProfile)
            relation = QCoreApplication::translate("GenerationsModel", "Current · system profile");
        else if (isCurrent)
            relation = QCoreApplication::translate("GenerationsModel", "Current");
        else if (isProfile)
            relation = QCoreApplication::translate("GenerationsModel", "System profile");
        m.insert(QStringLiteral("relationLabel"), relation);
        annotated.append(m);
    }

    m_generations = annotated;
    m_currentGeneration = current;
    m_available = true;
    m_error.clear();
    emit changed();
}

void GenerationsModel::retranslateUi()
{
    // Re-annotate relation labels without re-listing generations.
    QVariantList annotated;
    for (const QVariant &v : m_generations) {
        QVariantMap m = v.toMap();
        const bool isCurrent = m.value(QStringLiteral("current")).toBool();
        const bool isProfile = m.value(QStringLiteral("isProfile")).toBool();
        QString relation;
        if (isCurrent && isProfile)
            relation = tr("Current · system profile");
        else if (isCurrent)
            relation = tr("Current");
        else if (isProfile)
            relation = tr("System profile");
        m.insert(QStringLiteral("relationLabel"), relation);
        annotated.append(m);
    }
    m_generations = annotated;
    emit changed();
}

QVariantMap GenerationsModel::generationAt(int generation) const
{
    for (const QVariant &v : m_generations) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("generation")).toInt() == generation)
            return m;
    }
    return {};
}
