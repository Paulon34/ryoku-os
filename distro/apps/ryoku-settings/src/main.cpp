#include "ApplyController.h"
#include "BluetoothModel.h"
#include "DisplayModel.h"
#include "FlakeMetadataModel.h"
#include "FlakeUpdateModel.h"
#include "DesktopAppsModel.h"
#include "FlatpakAppsModel.h"
#include "GenerationsModel.h"
#include "GitStatusModel.h"
#include "LanguageManager.h"
#include "NetworkManagerModel.h"
#include "PaletteManager.h"
#include "PowerModel.h"
#include "RepoPath.h"
#include "SettingsStore.h"
#include "SoundModel.h"
#include "SystemInfoModel.h"
#include "WallpaperApplier.h"
#include "WallpaperGalleryModel.h"

#include <QCoreApplication>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>
#include <QtGlobal>

namespace {

void loadBrandingAssets(QGuiApplication &app)
{
    const int fontId = QFontDatabase::addApplicationFont(
        QStringLiteral(":/ryoku/fonts/MaterialSymbolsRounded-Ryoku.ttf"));
    if (fontId < 0)
        qWarning() << "ryoku.settings: Material Symbols icon font failed to load";
    else
        qInfo() << "ryoku.settings: icon font"
                << QFontDatabase::applicationFontFamilies(fontId);

    // Prefer theme/hicolor install; always register embedded assets as fallback.
    QIcon icon = QIcon::fromTheme(QString::fromUtf8(Ryoku::kIconName));
    icon.addFile(QStringLiteral(":/ryoku/icons/hicolor/128x128/apps/org.ryoku.Settings.png"));
    icon.addFile(QStringLiteral(":/ryoku/icons/hicolor/scalable/apps/org.ryoku.Settings.svg"));
    if (!icon.isNull())
        app.setWindowIcon(icon);
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QString::fromUtf8(Ryoku::kOrganizationName));
    app.setOrganizationDomain(QString::fromUtf8(Ryoku::kOrganizationDomain));
    app.setApplicationName(QString::fromUtf8(Ryoku::kAppDisplayName));
    app.setApplicationDisplayName(QString::fromUtf8(Ryoku::kAppDisplayName));
    app.setApplicationVersion(QStringLiteral(RYOKU_SETTINGS_VERSION));
    // Wayland app_id / portal lookup — basename without ".desktop".
    app.setDesktopFileName(QString::fromUtf8(Ryoku::kAppId));

    const bool smokeTest = app.arguments().contains(QStringLiteral("--smoke-test"));

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    loadBrandingAssets(app);

    const QString repoPath = Ryoku::resolveRepoPath();
    if (repoPath.isEmpty())
        qWarning() << "ryoku.settings: Could not resolve RYOKU_REPO_PATH; settings/git will be unavailable";
    else
        qInfo() << "ryoku.settings: Using repo path" << repoPath;

    LanguageManager languageManager;
    PaletteManager paletteManager;
    SettingsStore settingsStore;
    GitStatusModel git;
    WallpaperGalleryModel wallpaperGallery;
    WallpaperGalleryModel videoWallpaperGallery(WallpaperGalleryModel::MediaKind::Videos);
    WallpaperApplier wallpaperApplier;
    FlatpakAppsModel flatpakApps;
    DesktopAppsModel desktopApps;
    NetworkManagerModel networkModel;
    BluetoothModel bluetoothModel;
    SoundModel soundModel;
    DisplayModel displayModel;
    PowerModel powerModel;
    ApplyController applyController;
    SystemInfoModel systemInfo;
    FlakeMetadataModel flakeMetadata;
    FlakeUpdateModel flakeUpdate;
    GenerationsModel generationsModel;

    settingsStore.setRepoPath(repoPath);
    git.setRepoPath(repoPath);
    wallpaperGallery.setRepoPath(repoPath);
    videoWallpaperGallery.setRepoPath(repoPath);
    wallpaperApplier.setGalleryModel(&wallpaperGallery);
    wallpaperApplier.setVideoGalleryModel(&videoWallpaperGallery);
    flatpakApps.setDeclaredIds(settingsStore.flatpakDeclared());
    desktopApps.setRepoPath(repoPath);
    applyController.setSettingsStore(&settingsStore);
    applyController.setRepoPath(repoPath);
    flakeMetadata.setRepoPath(repoPath);
    flakeUpdate.setRepoPath(repoPath);
    flakeUpdate.setApplyController(&applyController);

    QQmlApplicationEngine engine;
    languageManager.setEngine(&engine);

    auto *ctx = engine.rootContext();
    ctx->setContextProperty(QStringLiteral("languageManager"), &languageManager);
    ctx->setContextProperty(QStringLiteral("paletteManager"), &paletteManager);
    ctx->setContextProperty(QStringLiteral("settingsStore"), &settingsStore);
    ctx->setContextProperty(QStringLiteral("settingsReader"), &settingsStore);
    ctx->setContextProperty(QStringLiteral("gitStatus"), &git);
    ctx->setContextProperty(QStringLiteral("wallpaperGallery"), &wallpaperGallery);
    ctx->setContextProperty(QStringLiteral("videoWallpaperGallery"), &videoWallpaperGallery);
    ctx->setContextProperty(QStringLiteral("wallpaperApplier"), &wallpaperApplier);
    ctx->setContextProperty(QStringLiteral("flatpakApps"), &flatpakApps);
    ctx->setContextProperty(QStringLiteral("desktopApps"), &desktopApps);
    ctx->setContextProperty(QStringLiteral("networkModel"), &networkModel);
    ctx->setContextProperty(QStringLiteral("bluetoothModel"), &bluetoothModel);
    ctx->setContextProperty(QStringLiteral("soundModel"), &soundModel);
    ctx->setContextProperty(QStringLiteral("displayModel"), &displayModel);
    ctx->setContextProperty(QStringLiteral("powerModel"), &powerModel);
    ctx->setContextProperty(QStringLiteral("applyController"), &applyController);
    ctx->setContextProperty(QStringLiteral("systemInfo"), &systemInfo);
    ctx->setContextProperty(QStringLiteral("flakeMetadata"), &flakeMetadata);
    ctx->setContextProperty(QStringLiteral("flakeUpdate"), &flakeUpdate);
    ctx->setContextProperty(QStringLiteral("generationsModel"), &generationsModel);
    ctx->setContextProperty(QStringLiteral("repoPath"), repoPath);
    ctx->setContextProperty(QStringLiteral("appVersion"), app.applicationVersion());
    ctx->setContextProperty(QStringLiteral("qtRuntimeVersion"), QString::fromLatin1(qVersion()));
    ctx->setContextProperty(QStringLiteral("appId"), QString::fromUtf8(Ryoku::kAppId));
    ctx->setContextProperty(QStringLiteral("appDisplayName"),
                            QString::fromUtf8(Ryoku::kAppDisplayName));

    // C++ label properties need a NOTIFY after QTranslator swap (QML qsTr is covered by retranslate).
    auto refreshCppUi = [&]() {
        applyController.retranslateUi();
        git.retranslateUi();
        settingsStore.retranslateUi();
        networkModel.retranslateUi();
        bluetoothModel.retranslateUi();
        flatpakApps.retranslateUi();
        desktopApps.retranslateUi();
        flakeUpdate.retranslateUi();
        generationsModel.retranslateUi();
    };
    QObject::connect(&languageManager, &LanguageManager::languageChanged, &app, refreshCppUi);

    int smokeExit = 0;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [&smokeExit, smokeTest]() {
            qCritical("ryoku.settings: QQmlApplicationEngine failed to load Main");
            smokeExit = 1;
            QCoreApplication::exit(smokeTest ? 1 : -1);
        },
        Qt::QueuedConnection);

    engine.loadFromModule("Ryoku.Settings", "Main");

    if (engine.rootObjects().isEmpty()) {
        qCritical("ryoku.settings: loadFromModule(Ryoku.Settings, Main) produced no rootObjects "
                  "(check QTP0001 / RESOURCE_PREFIX /qt/qml)");
        return smokeTest ? 1 : -1;
    }

    if (smokeTest) {
        // StackLayout instantiates Appearance + Git e atualizações with Main; also
        // probe the module types directly so CI fails on page-level QML errors.
        QQmlComponent appearance(&engine);
        appearance.loadFromModule(u"Ryoku.Settings", u"AppearancePage");
        if (appearance.isError() || !appearance.isReady()) {
            qCritical() << "ryoku.settings smoke: AppearancePage:" << appearance.errors();
            return 3;
        }
        QObject *appearanceObj = appearance.create(engine.rootContext());
        if (!appearanceObj) {
            qCritical() << "ryoku.settings smoke: AppearancePage create failed:"
                        << appearance.errors();
            return 3;
        }
        appearanceObj->deleteLater();

        QQmlComponent gitPage(&engine);
        gitPage.loadFromModule(u"Ryoku.Settings", u"NixUpdatesPage");
        if (gitPage.isError() || !gitPage.isReady()) {
            qCritical() << "ryoku.settings smoke: NixUpdatesPage:" << gitPage.errors();
            return 4;
        }
        QObject *gitObj = gitPage.create(engine.rootContext());
        if (!gitObj) {
            qCritical() << "ryoku.settings smoke: NixUpdatesPage create failed:"
                        << gitPage.errors();
            return 4;
        }
        gitObj->deleteLater();

        QObject *root = engine.rootObjects().constFirst();
        // indices: home=0 appearance=1 … nix=9 (Git e atualizações)
        QMetaObject::invokeMethod(root, "goToPage", Q_ARG(QVariant, QVariant(1)),
                                  Q_ARG(QVariant, QVariant(1)));
        QMetaObject::invokeMethod(root, "goToPage", Q_ARG(QVariant, QVariant(9)),
                                  Q_ARG(QVariant, QVariant(1)));

        QTimer::singleShot(0, &app, [&smokeExit]() {
            if (smokeExit == 0) {
                qInfo("ryoku.settings smoke: PASS (Main + Appearance + Git pages)");
                QCoreApplication::exit(0);
            }
        });
    }

    return app.exec();
}
