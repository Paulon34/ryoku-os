#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVector>

// Catalog of desktop apps from APT manifests + Flatpak declared/installed +
// optional Nix HM profile binaries. Origin badges: APT | Flatpak | Nix.
class DesktopAppsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool helperAvailable READ helperAvailable NOTIFY changed)
    Q_PROPERTY(QString repoPath READ repoPath WRITE setRepoPath NOTIFY repoPathChanged)

public:
    enum Origin {
        Apt = 0,
        Flatpak = 1,
        Nix = 2,
    };
    Q_ENUM(Origin)

    enum InstallStatus {
        NotInstalled = 0,
        Installed = 1,
        Unknown = 2,
    };
    Q_ENUM(InstallStatus)

    enum Roles {
        AppIdRole = Qt::UserRole + 1,
        NameRole,
        OriginRole,
        OriginLabelRole,
        StatusRole,
        StatusLabelRole,
        VersionRole,
        IconNameRole,
        CanInstallRole,
        CanUpdateRole,
        CanRemoveRole,
    };

    struct Row {
        QString appId;
        QString name;
        Origin origin = Apt;
        InstallStatus status = Unknown;
        QString version;
        QString iconName;
        bool canInstall = false;
        bool canUpdate = false;
        bool canRemove = false;
    };

    explicit DesktopAppsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_rows.size(); }
    QString error() const { return m_error; }
    bool busy() const { return m_busy; }
    bool helperAvailable() const { return !m_helperPath.isEmpty(); }

    QString repoPath() const { return m_repoPath; }
    void setRepoPath(const QString &path);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void retranslateUi();
    Q_INVOKABLE bool installApp(const QString &appId, int origin);
    Q_INVOKABLE bool updateApp(const QString &appId, int origin);
    Q_INVOKABLE bool removeApp(const QString &appId, int origin);

    static QString findPkgHelper();
    static QString originLabel(Origin o);

signals:
    void changed();
    void busyChanged();
    void repoPathChanged();
    void operationFinished(bool ok, const QString &message);

private:
    void rebuild();
    void loadAptCatalog();
    void loadFlatpakRows();
    void loadNixHints();
    bool runPkexecHelper(const QStringList &helperArgs, QString *errorOut);

    QString m_repoPath;
    QString m_helperPath;
    QString m_error;
    bool m_busy = false;
    QVector<Row> m_rows;
};
