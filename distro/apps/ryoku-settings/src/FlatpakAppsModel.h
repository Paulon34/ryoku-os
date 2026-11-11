#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVector>

// Read-only inventory of Flatpak apps + classification against declared IDs.
class FlatpakAppsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(int managedCount READ managedCount NOTIFY changed)
    Q_PROPERTY(int localCount READ localCount NOTIFY changed)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QStringList declaredIds READ declaredIds WRITE setDeclaredIds NOTIFY declaredIdsChanged)

public:
    enum Status {
        Managed = 0,  // declared + installed
        Pending = 1,  // declared + not installed
        Local = 2,    // installed + not declared
    };
    Q_ENUM(Status)

    enum Roles {
        ApplicationIdRole = Qt::UserRole + 1,
        NameRole,
        StatusRole,
        StatusLabelRole,
        DeclaredRole,
        InstalledRole,
    };

    struct InstalledApp {
        QString applicationId;
        QString name;
    };

    struct ClassifiedApp {
        QString applicationId;
        QString name;
        Status status = Local;
    };

    explicit FlatpakAppsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_rows.size(); }
    int managedCount() const;
    int localCount() const;
    int pendingCount() const;
    QString error() const { return m_error; }
    bool busy() const { return m_busy; }

    QStringList declaredIds() const { return m_declaredIds; }
    void setDeclaredIds(const QStringList &ids);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void retranslateUi();

    // Pure helpers / tests.
    static QVector<InstalledApp> parseFlatpakListOutput(const QByteArray &stdoutBytes);
    static QVector<ClassifiedApp> classify(const QStringList &declared,
                                           const QVector<InstalledApp> &installed);
    static QString findFlatpakBinary();

signals:
    void changed();
    void busyChanged();
    void declaredIdsChanged();

private:
    void rebuild();

    QStringList m_declaredIds;
    QVector<InstalledApp> m_installed;
    QVector<ClassifiedApp> m_rows;
    QString m_error;
    bool m_busy = false;
};
