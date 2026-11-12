#include "FlatpakAppsModel.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>
#include <algorithm>

Q_LOGGING_CATEGORY(lcFlatpakApps, "ryoku.settings.flatpak")

FlatpakAppsModel::FlatpakAppsModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int FlatpakAppsModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QVariant FlatpakAppsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};

    const ClassifiedApp &row = m_rows.at(index.row());
    switch (role) {
    case ApplicationIdRole:
        return row.applicationId;
    case NameRole:
        return row.name.isEmpty() ? row.applicationId : row.name;
    case StatusRole:
        return static_cast<int>(row.status);
    case StatusLabelRole:
        switch (row.status) {
        case Managed:
            return QCoreApplication::translate("FlatpakAppsModel", "Managed by Ryoku");
        case Pending:
            return QCoreApplication::translate("FlatpakAppsModel", "Pending install / Needs Apply");
        case Local:
            return QCoreApplication::translate("FlatpakAppsModel", "Installed locally");
        }
        return {};
    case DeclaredRole:
        return row.status == Managed || row.status == Pending;
    case InstalledRole:
        return row.status == Managed || row.status == Local;
    default:
        return {};
    }
}

QHash<int, QByteArray> FlatpakAppsModel::roleNames() const
{
    return {
        {ApplicationIdRole, "applicationId"},
        {NameRole, "name"},
        {StatusRole, "status"},
        {StatusLabelRole, "statusLabel"},
        {DeclaredRole, "declared"},
        {InstalledRole, "installed"},
    };
}

int FlatpakAppsModel::managedCount() const
{
    int n = 0;
    for (const auto &r : m_rows)
        if (r.status == Managed)
            ++n;
    return n;
}

int FlatpakAppsModel::localCount() const
{
    int n = 0;
    for (const auto &r : m_rows)
        if (r.status == Local)
            ++n;
    return n;
}

int FlatpakAppsModel::pendingCount() const
{
    int n = 0;
    for (const auto &r : m_rows)
        if (r.status == Pending)
            ++n;
    return n;
}

void FlatpakAppsModel::setDeclaredIds(const QStringList &ids)
{
    if (m_declaredIds == ids)
        return;
    m_declaredIds = ids;
    emit declaredIdsChanged();
    rebuild();
}

QString FlatpakAppsModel::findFlatpakBinary()
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("flatpak"));
    if (!fromPath.isEmpty())
        return fromPath;
    const QString systemPath = QStringLiteral("/run/current-system/sw/bin/flatpak");
    if (QFileInfo::exists(systemPath) && QFileInfo(systemPath).isExecutable())
        return systemPath;
    return {};
}

QVector<FlatpakAppsModel::InstalledApp> FlatpakAppsModel::parseFlatpakListOutput(const QByteArray &stdoutBytes)
{
    QVector<InstalledApp> out;
    const QString text = QString::fromUtf8(stdoutBytes);
    const QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty())
            continue;
        // Prefer tab-separated (flatpak --columns). Fall back to first whitespace split.
        QString appId;
        QString name;
        if (line.contains(QLatin1Char('\t'))) {
            const QStringList cols = line.split(QLatin1Char('\t'));
            if (cols.isEmpty())
                continue;
            appId = cols.at(0).trimmed();
            if (cols.size() > 1)
                name = cols.at(1).trimmed();
        } else {
            const int sp = line.indexOf(QLatin1Char(' '));
            if (sp < 0) {
                appId = line;
            } else {
                appId = line.left(sp).trimmed();
                name = line.mid(sp + 1).trimmed();
            }
        }
        if (appId.isEmpty() || appId == QLatin1String("Application") || appId == QLatin1String("application"))
            continue;
        InstalledApp app;
        app.applicationId = appId;
        app.name = name;
        out.append(app);
    }
    return out;
}

QVector<FlatpakAppsModel::ClassifiedApp> FlatpakAppsModel::classify(const QStringList &declared,
                                                                   const QVector<InstalledApp> &installed)
{
    QHash<QString, QString> installedNames;
    for (const auto &app : installed)
        installedNames.insert(app.applicationId, app.name);

    QSet<QString> declaredSet;
    for (const QString &id : declared)
        declaredSet.insert(id);

    QVector<ClassifiedApp> rows;

    // Declared first (managed or pending), sorted by id.
    QStringList declaredSorted = declared;
    declaredSorted.removeDuplicates();
    std::sort(declaredSorted.begin(), declaredSorted.end());
    for (const QString &id : declaredSorted) {
        ClassifiedApp row;
        row.applicationId = id;
        if (installedNames.contains(id)) {
            row.name = installedNames.value(id);
            row.status = Managed;
        } else {
            row.name = id;
            row.status = Pending;
        }
        rows.append(row);
    }

    // Local-only installed apps, sorted by id.
    QStringList localIds;
    for (const auto &app : installed) {
        if (!declaredSet.contains(app.applicationId))
            localIds.append(app.applicationId);
    }
    localIds.removeDuplicates();
    std::sort(localIds.begin(), localIds.end());
    for (const QString &id : localIds) {
        ClassifiedApp row;
        row.applicationId = id;
        row.name = installedNames.value(id);
        if (row.name.isEmpty())
            row.name = id;
        row.status = Local;
        rows.append(row);
    }

    return rows;
}

void FlatpakAppsModel::rebuild()
{
    beginResetModel();
    m_rows = classify(m_declaredIds, m_installed);
    endResetModel();
    emit changed();
}

void FlatpakAppsModel::refresh()
{
    if (m_busy)
        return;

    m_error.clear();
    m_busy = true;
    emit busyChanged();

    const QString flatpak = findFlatpakBinary();
    if (flatpak.isEmpty()) {
        m_installed.clear();
        m_error = QStringLiteral("flatpak not found");
        qWarning(lcFlatpakApps) << m_error;
        rebuild();
        m_busy = false;
        emit busyChanged();
        emit changed();
        return;
    }

    QProcess proc;
    proc.setProgram(flatpak);
    // argv only — never shell.
    proc.setArguments({
        QStringLiteral("list"),
        QStringLiteral("--app"),
        QStringLiteral("--columns=application,name"),
    });
    proc.setProcessChannelMode(QProcess::SeparateChannels);
    proc.start();

    if (!proc.waitForFinished(15000)) {
        proc.kill();
        m_installed.clear();
        m_error = QStringLiteral("flatpak list timed out");
        qWarning(lcFlatpakApps) << m_error;
        rebuild();
        m_busy = false;
        emit busyChanged();
        emit changed();
        return;
    }

    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        m_installed.clear();
        m_error = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        if (m_error.isEmpty())
            m_error = QStringLiteral("flatpak list failed (exit %1)").arg(proc.exitCode());
        qWarning(lcFlatpakApps) << m_error;
        rebuild();
        m_busy = false;
        emit busyChanged();
        emit changed();
        return;
    }

    m_installed = parseFlatpakListOutput(proc.readAllStandardOutput());
    qInfo(lcFlatpakApps) << "installed flatpaks:" << m_installed.size();
    rebuild();
    m_busy = false;
    emit busyChanged();
    emit changed();
}

void FlatpakAppsModel::retranslateUi()
{
    if (rowCount() > 0)
        emit dataChanged(index(0, 0), index(rowCount() - 1, 0));
    emit changed();
}
