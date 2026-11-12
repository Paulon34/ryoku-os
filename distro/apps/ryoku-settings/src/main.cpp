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
#include <QQmlContext>
#include <QQuickStyle>
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

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("Ryoku.Settings", "Main");

    return app.exec();
}
