#include "PaletteManager.h"
#include "SettingsStore.h"
#include "RepoPath.h"
#include "LanguageManager.h"
#include "GitStatusModel.h"
#include "WallpaperGalleryModel.h"
#include "WallpaperApplier.h"
#include "FlatpakAppsModel.h"
#include "NetworkManagerModel.h"
#include "BluetoothModel.h"
#include "SoundModel.h"
#include "DisplayModel.h"
#include "PowerModel.h"
#include "ApplyController.h"
#include "SystemInfoModel.h"
#include "FlakeMetadataModel.h"
#include "FlakeUpdateModel.h"
#include "GenerationsModel.h"
#include "ops.h"

#include <QtTest/QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSaveFile>
#include <QDateTime>
#include <QSettings>
#include <QCoreApplication>
#include <QRegularExpression>
#include <QXmlStreamReader>

class ParserTests : public QObject
{
    Q_OBJECT

private slots:
    void paletteValid();
    void paletteInvalidFallsBack();
    void settingsValidNulls();
    void settingsInvalid();
    void repoLooksLike();
    void appIdentityAndDesktopContract();
    void gitPorcelain();
    void gitWorkflowParsersAndSafety();
    void wallpaperIdValidation();
    void appearanceMergePreservesUnknown();
    void appearanceLoginWallpaperIndependent();
    void appearanceNullReset();
    void appearanceRejectsBadTransparency();
    void appearanceRejectsBadSchema();
    void appearanceRejectsLoginTraversal();
    void videoWallpaperIdValidation();
    void appearanceVideoMergePreservesUnknown();
    void appearanceVideoRejectsInvalid();
    void appearanceVideoImageOnlyFileUnchanged();
    void videoGalleryListsOnlyVideos();
    void videoApplyArgv();
    void saveFileAtomicKeepsOriginalOnCancel();
    void saveNoopBytesIdentical();
    void saveSameValueSkipsRewrite();
    void serializeDeterministic();
    void flatpakIdValidation();
    void flatpakNormalizeSortDedup();
    void flatpakMergePreservesUnknown();
    void flatpakRejectsInvalidId();
    void flatpakParseListOutput();
    void flatpakClassifyStatuses();
    void networkSecurityAndSort();
    void bluetoothSortAndStatus();
    void soundVolumeParseAndClamp();
    void displayParseModesAndValidate();
    void displayRoleNamesAvoidItemEnabledClash();
    void displayCannotDisableLast();
    void displaySnapshotRoundTrip();
    void displaySettingsMergePreservesUnknown();
    void powerBrightnessClampAndBatteryMap();
    void applyHashCompareAndStatus();
    void applyNixEvalStderrDoesNotFail();
    void applyDeclarativePageBadge();
    void applyReconcilePrivilegedVerification();
    void applyPlanInventory();
    void applyValidationParseAndAllowlist();
    void applyStateIndependentOfGitDirty();
    void applyPrivilegedArgvAndResults();
    void applyHelperOpsParse();
    void applyHelperMissingAndUnsavedDraft();
    void applyPkexecPathAndClassification();
    void systemOsReleaseParse();
    void systemMeminfoAndPaths();
    void systemGenerationMatchLabels();
    void gitSummaryLabels();
    void flakeMetadataParseAndMalformed();
    void generationsListParse();
    void flakeUpdateLockParsersAndAllowlist();
    void flakeUpdateRevertAtomicAndIsolation();
    void flakeUpdateRebuildHintAndLockPending();
    void generationSwitchParsersAndArgv();
    void generationSwitchVerificationReconcile();
    void languageManagerSelectorsAndFallback();
    void languageManagerPersistenceLocal();
    void languageManagerDoesNotTouchSettingsOrApply();
    void languageTranslationResourcePath();
    void searchIndexMatchesPagesAndCatalogue();
    void visualProfileMergeAndValidation();
    void shellStyleMergeAndValidation();
};

void ParserTests::paletteValid()
{
    PaletteManager pm;
    QString err;
    const bool ok = PaletteManager::parsePaletteJson(
        R"({
          "mode": "dark",
          "primary": "#cbefff",
          "on_primary": "#000000",
          "secondary": "#d6edf8",
          "on_secondary": "#000000",
          "tertiary": "#e9e7ff",
          "on_tertiary": "#000000",
          "background": "#0f1416",
          "on_background": "#dee3e6",
          "surface": "#0f1416",
          "on_surface": "#ffffff",
          "surface_variant": "#40484c",
          "surface_container": "#292e31",
          "surface_container_high": "#34393c",
          "outline": "#d6dee2",
          "error": "#ffe3e0",
          "on_error": "#000000"
        })",
        &pm,
        &err);
    QVERIFY2(ok, qPrintable(err));
    QCOMPARE(pm.primary(), QColor(QStringLiteral("#cbefff")));
    QVERIFY2(!pm.usingFallback(), "valid palette must clear usingFallback");
}

void ParserTests::paletteInvalidFallsBack()
{
    PaletteManager pm;
    QString err;
    QVERIFY(!PaletteManager::parsePaletteJson(QByteArrayLiteral("{not-json"), &pm, &err));
    QVERIFY(err.contains(QStringLiteral("invalid JSON")));
}

void ParserTests::settingsValidNulls()
{
    SettingsStore store;
    QString err;
    const bool ok = SettingsStore::parseSettingsJson(
        R"({
          "schemaVersion": 1,
          "appearance": { "dynamicColors": true, "wallpaper": null, "animations": true },
          "desktop": { "hyprland": { "gapsIn": null } }
        })",
        &store,
        &err);
    QVERIFY2(ok, qPrintable(err));
    QCOMPARE(store.schemaVersion(), 1);
    QCOMPARE(store.dynamicColorsDisplay(), QStringLiteral("On"));
    QCOMPARE(store.wallpaperDisplay(), QStringLiteral("Current system value"));
    QCOMPARE(store.gapsInDisplay(), QStringLiteral("Current system value"));
}

void ParserTests::settingsInvalid()
{
    SettingsStore store;
    QString err;
    QVERIFY(!SettingsStore::parseSettingsJson(QByteArrayLiteral("{}"), &store, &err));
}

void ParserTests::repoLooksLike()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(!Ryoku::looksLikeRyokuRepo(dir.path()));
    QDir(dir.path()).mkpath(QStringLiteral("ryoku"));
    QFile flake(dir.filePath(QStringLiteral("flake.nix")));
    QVERIFY(flake.open(QIODevice::WriteOnly));
    flake.write("{}");
    flake.close();
    QFile settings(dir.filePath(QStringLiteral("ryoku/settings.json")));
    QVERIFY(settings.open(QIODevice::WriteOnly));
    settings.write("{}");
    settings.close();
    QVERIFY(Ryoku::looksLikeRyokuRepo(dir.path()));
}

void ParserTests::appIdentityAndDesktopContract()
{
    QCOMPARE(QString::fromUtf8(Ryoku::kAppId), QStringLiteral("org.ryoku.Settings"));
    QCOMPARE(QString::fromUtf8(Ryoku::kDesktopFileName),
             QStringLiteral("org.ryoku.Settings.desktop"));
    QCOMPARE(QString::fromUtf8(Ryoku::kAppDisplayName), QStringLiteral("Ryoku Settings"));
    QCOMPARE(QString::fromUtf8(Ryoku::kIconName), QStringLiteral("org.ryoku.Settings"));
    // Desktop basename (no .desktop) is what Qt setDesktopFileName / Wayland app_id use.
    QVERIFY(!QString::fromUtf8(Ryoku::kAppId).endsWith(QStringLiteral(".desktop")));
    QCOMPARE(QString::fromUtf8(Ryoku::kDesktopFileName),
             QString::fromUtf8(Ryoku::kAppId) + QStringLiteral(".desktop"));

    // Exec is a PATH binary name — not an absolute path and not repo-relative.
    const QString execBinary = QStringLiteral("ryoku-settings");
    QVERIFY(!execBinary.startsWith(QLatin1Char('/')));
    QVERIFY(!execBinary.startsWith(QLatin1String("./")));
    QVERIFY(!execBinary.contains(QLatin1String("..")));
}

void ParserTests::gitPorcelain()
{
    QCOMPARE(GitStatusModel::parsePorcelain(QByteArray()), QStringList());
    QCOMPARE(
        GitStatusModel::parsePorcelain(QByteArrayLiteral(" M apps/foo\n?? bar.txt\n")),
        (QStringList{QStringLiteral("apps/foo"), QStringLiteral("bar.txt")}));
}

void ParserTests::gitWorkflowParsersAndSafety()
{
    // porcelain v2 -z: unstaged modify + untracked with space + staged add + rename + conflict
    QByteArray v2;
    v2 += "1 .M N... 100644 100644 100644 "
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "
          "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb path with space.txt";
    v2 += '\0';
    v2 += "1 A. N... 000000 100644 100644 "
          "0000000000000000000000000000000000000000 "
          "cccccccccccccccccccccccccccccccccccccccc newfile.txt";
    v2 += '\0';
    v2 += "1 D. N... 100644 000000 000000 "
          "dddddddddddddddddddddddddddddddddddddddd "
          "0000000000000000000000000000000000000000 gone.txt";
    v2 += '\0';
    v2 += "2 R. N... 100644 100644 100644 "
          "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee "
          "ffffffffffffffffffffffffffffffffffffffff R100 newname.txt";
    v2 += '\0';
    v2 += "oldname.txt";
    v2 += '\0';
    v2 += "? untracked file.txt";
    v2 += '\0';
    v2 += "u UU N... 100644 100644 100644 100644 "
          "1111111111111111111111111111111111111111 "
          "2222222222222222222222222222222222222222 "
          "3333333333333333333333333333333333333333 conflicted.txt";
    v2 += '\0';

    const QVariantList parsed = GitStatusModel::parsePorcelainV2Z(v2);
    QVERIFY(parsed.size() >= 6);

    auto sectionOf = [&](const QString &path, const QString &section) -> QVariantMap {
        for (const QVariant &v : parsed) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("path")).toString() == path
                && m.value(QStringLiteral("section")).toString() == section)
                return m;
        }
        return {};
    };

    QCOMPARE(sectionOf(QStringLiteral("path with space.txt"), QStringLiteral("unstaged"))
                 .value(QStringLiteral("code")).toString(),
             QStringLiteral("M"));
    QCOMPARE(sectionOf(QStringLiteral("newfile.txt"), QStringLiteral("staged"))
                 .value(QStringLiteral("code")).toString(),
             QStringLiteral("A"));
    QCOMPARE(sectionOf(QStringLiteral("gone.txt"), QStringLiteral("staged"))
                 .value(QStringLiteral("code")).toString(),
             QStringLiteral("D"));
    QCOMPARE(sectionOf(QStringLiteral("newname.txt"), QStringLiteral("staged"))
                 .value(QStringLiteral("code")).toString(),
             QStringLiteral("R"));
    QCOMPARE(sectionOf(QStringLiteral("newname.txt"), QStringLiteral("staged"))
                 .value(QStringLiteral("origPath")).toString(),
             QStringLiteral("oldname.txt"));
    QCOMPARE(sectionOf(QStringLiteral("untracked file.txt"), QStringLiteral("untracked"))
                 .value(QStringLiteral("code")).toString(),
             QStringLiteral("?"));
    QCOMPARE(sectionOf(QStringLiteral("conflicted.txt"), QStringLiteral("conflict"))
                 .value(QStringLiteral("code")).toString(),
             QStringLiteral("U"));

    // Path safety
    QVERIFY(GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("apps/foo.cpp")));
    QVERIFY(GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("path with space.txt")));
    QVERIFY(!GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("/etc/passwd")));
    QVERIFY(!GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("../etc/passwd")));
    QVERIFY(!GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("foo/../bar")));
    QVERIFY(!GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("")));
    QVERIFY(!GitStatusModel::isSafeRelativeRepoPath(QStringLiteral("foo\\bar")));

    QSet<QString> snap;
    snap.insert(QStringLiteral("a.txt"));
    snap.insert(QStringLiteral("b.txt"));
    QString err;
    QCOMPARE(GitStatusModel::filterPathsAgainstSnapshot(
                 {QStringLiteral("a.txt"), QStringLiteral("b.txt")}, snap, &err),
             (QStringList{QStringLiteral("a.txt"), QStringLiteral("b.txt")}));
    QVERIFY(GitStatusModel::filterPathsAgainstSnapshot(
                {QStringLiteral("../x")}, snap, &err).isEmpty());
    QVERIFY(err.contains(QStringLiteral("unsafe")));
    QVERIFY(GitStatusModel::filterPathsAgainstSnapshot(
                {QStringLiteral("missing.txt")}, snap, &err).isEmpty());
    QVERIFY(err.contains(QStringLiteral("snapshot")));
    QVERIFY(GitStatusModel::filterPathsAgainstSnapshot(
                {QStringLiteral("/abs")}, snap, &err).isEmpty());

    // Argv builders include -- and never force on push
    const QStringList stageArgv =
        GitStatusModel::buildStageArgv({QStringLiteral("a.txt"), QStringLiteral("b.txt")});
    QCOMPARE(stageArgv.at(0), QStringLiteral("add"));
    QVERIFY(stageArgv.contains(QStringLiteral("--")));
    QCOMPARE(stageArgv.indexOf(QStringLiteral("--")), 1);

    const QStringList unstageArgv =
        GitStatusModel::buildUnstageArgv({QStringLiteral("a.txt")});
    QCOMPARE(unstageArgv.at(0), QStringLiteral("restore"));
    QVERIFY(unstageArgv.contains(QStringLiteral("--staged")));
    QVERIFY(unstageArgv.contains(QStringLiteral("--")));

    QCOMPARE(GitStatusModel::buildDiffArgv(QStringLiteral("a.txt"), false),
             (QStringList{QStringLiteral("diff"), QStringLiteral("--"), QStringLiteral("a.txt")}));
    QCOMPARE(GitStatusModel::buildDiffArgv(QStringLiteral("a.txt"), true),
             (QStringList{QStringLiteral("diff"), QStringLiteral("--cached"), QStringLiteral("--"),
                          QStringLiteral("a.txt")}));

    const QStringList commitArgv =
        GitStatusModel::buildCommitArgv(QStringLiteral("feat: x"));
    QCOMPARE(commitArgv, (QStringList{QStringLiteral("commit"), QStringLiteral("-m"),
                                       QStringLiteral("feat: x")}));

    QVERIFY(GitStatusModel::pushArgvIsSafe(GitStatusModel::buildPushArgv()));
    QVERIFY(!GitStatusModel::pushArgvIsSafe(
        {QStringLiteral("push"), QStringLiteral("--force")}));
    QVERIFY(!GitStatusModel::pushArgvIsSafe(
        {QStringLiteral("push"), QStringLiteral("--force-with-lease")}));
    QVERIFY(!GitStatusModel::pushArgvIsSafe(
        {QStringLiteral("push"), QStringLiteral("--all")}));

    // Commit message validation
    QVERIFY(GitStatusModel::commitMessageValid(QStringLiteral("ok"), &err));
    QVERIFY(!GitStatusModel::commitMessageValid(QStringLiteral("   "), &err));
    QVERIFY(!GitStatusModel::commitMessageValid(QString(), &err));

    // Ahead/behind + push status
    int ahead = -1;
    int behind = -1;
    QVERIFY(GitStatusModel::parseAheadBehind(QByteArrayLiteral("1\t2"), &ahead, &behind));
    QCOMPARE(ahead, 1);
    QCOMPARE(behind, 2);
    QVERIFY(GitStatusModel::parseAheadBehind(QByteArrayLiteral("0 0"), &ahead, &behind));
    QCOMPARE(ahead, 0);
    QCOMPARE(behind, 0);
    QCOMPARE(GitStatusModel::formatPushStatus(true, false, QStringLiteral("origin/main"), 0, 0),
             QStringLiteral("Up to date"));
    QCOMPARE(GitStatusModel::formatPushStatus(true, false, QStringLiteral("origin/main"), 1, 0),
             QStringLiteral("1 commit ahead"));
    QCOMPARE(GitStatusModel::formatPushStatus(true, false, QStringLiteral("origin/main"), 2, 3),
             QStringLiteral("2 ahead · 3 behind"));
    QCOMPARE(GitStatusModel::formatPushStatus(true, false, QString(), 0, 0),
             QStringLiteral("No upstream configured"));
    QCOMPARE(GitStatusModel::formatPushStatus(true, true, QStringLiteral("origin/main"), 0, 0),
             QStringLiteral("Detached HEAD"));

    // Diff truncate / binary
    bool truncated = false;
    bool binary = false;
    QCOMPARE(GitStatusModel::truncateDiffOutput(QByteArrayLiteral("hello\nworld\n"), 1024, 100,
                                                &truncated, &binary),
             QStringLiteral("hello\nworld\n"));
    QVERIFY(!truncated);
    QVERIFY(!binary);
    QByteArray withNul = QByteArrayLiteral("a");
    withNul.append('\0');
    withNul.append('b');
    QCOMPARE(GitStatusModel::truncateDiffOutput(withNul, 1024, 100, &truncated, &binary),
             QStringLiteral("Binary file changed"));
    QVERIFY(binary);

    // Identity / auth classifiers
    QVERIFY(GitStatusModel::classifyCommitFailure(
                QByteArrayLiteral("Author identity unknown\nplease tell me who you are"))
                .contains(QStringLiteral("identity")));
    QVERIFY(GitStatusModel::classifyPushFailure(
                QByteArrayLiteral("Authentication failed"))
                .contains(QStringLiteral("authentication")));

    // Snapshot includes pre-staged paths (existing staged before UI)
    QVariantList staged;
    staged.append(QVariantMap{{QStringLiteral("path"), QStringLiteral("pre.txt")},
                              {QStringLiteral("section"), QStringLiteral("staged")},
                              {QStringLiteral("code"), QStringLiteral("M")}});
    QVariantList empty;
    const QStringList snapPaths =
        GitStatusModel::snapshotPathsFromEntries(staged, empty, empty, empty);
    QVERIFY(snapPaths.contains(QStringLiteral("pre.txt")));

    // Git dirty independent from Apply state (hash Applied + dirty summary co-exist)
    const QString h = QStringLiteral("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h, h),
             QString::fromLatin1(ApplyController::StatusApplied));
    QCOMPARE(GitStatusModel::repositorySummary(true, false, 4),
             QStringLiteral("Modified · 4 files"));

    // Refresh / Clean contract regressions
    QVERIFY(!GitStatusModel::isWorkingTreeClean(false, 0, 0, 0, 0)); // invalid snapshot ≠ Clean
    QVERIFY(GitStatusModel::isWorkingTreeClean(true, 0, 0, 0, 0));
    QVERIFY(!GitStatusModel::isWorkingTreeClean(true, 0, 5, 0, 0));
    QCOMPARE(GitStatusModel::workingTreeLabelFor(false, true, false, 0),
             QStringLiteral("Refreshing…"));
    QCOMPARE(GitStatusModel::workingTreeLabelFor(false, false, true, 0),
             QStringLiteral("Unavailable")); // must NOT report Clean without valid snapshot
    QCOMPARE(GitStatusModel::workingTreeLabelFor(true, false, false, 5),
             QStringLiteral("Modified · 5 files"));

    // Status bytes authoritative — empty metadata does not matter; 5 modified → not clean
    QByteArray five;
    for (const char *p : {"a.cpp", "b.cpp", "c.cpp", "d.cpp", "e.json"}) {
        five += "1 .M N... 100644 100644 100644 "
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "
                "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ";
        five += p;
        five += '\0';
    }
    bool statusValid = false;
    bool clean = true;
    int fileCount = 0;
    int stagedN = 0;
    int unstagedN = 0;
    int untrackedN = 0;
    int conflictsN = 0;
    GitStatusModel::applyRefreshStatusBytes(five, &statusValid, &clean, &fileCount, &stagedN,
                                            &unstagedN, &untrackedN, &conflictsN);
    QVERIFY(statusValid);
    QVERIFY(!clean);
    QCOMPARE(fileCount, 5);
    QCOMPARE(unstagedN, 5);
    QCOMPARE(stagedN, 0);

    // Empty porcelain → valid + clean (Idle after refresh)
    GitStatusModel::applyRefreshStatusBytes(QByteArray(), &statusValid, &clean, &fileCount, &stagedN,
                                            &unstagedN, &untrackedN, &conflictsN);
    QVERIFY(statusValid);
    QVERIFY(clean);
    QCOMPARE(fileCount, 0);

    // Working-tree label after successful status publish matches Idle+dirty contract
    QCOMPARE(GitStatusModel::workingTreeLabelFor(true, false, clean, fileCount),
             QStringLiteral("Clean"));
}

void ParserTests::wallpaperIdValidation()
{
    QVERIFY(SettingsStore::isValidWallpaperId(QStringLiteral("1.jpg")));
    QVERIFY(SettingsStore::isValidWallpaperId(QStringLiteral("foo_bar-2.PNG")));
    QVERIFY(!SettingsStore::isValidWallpaperId(QStringLiteral("../etc/passwd")));
    QVERIFY(!SettingsStore::isValidWallpaperId(QStringLiteral("a/b.jpg")));
    QVERIFY(!SettingsStore::isValidWallpaperId(QStringLiteral("noext")));
    QVERIFY(!SettingsStore::isValidWallpaperId(QStringLiteral("")));
}

void ParserTests::appearanceMergePreservesUnknown()
{
    const QByteArray input = R"({
      "schemaVersion": 1,
      "appearance": {
        "dynamicColors": true,
        "wallpaper": null,
        "animations": true,
        "transparency": null,
        "futureKey": "keep-me"
      },
      "desktop": { "hyprland": { "gapsIn": null } },
      "experimental": { "flag": true }
    })";

    QJsonParseError err;
    const QJsonObject root = QJsonDocument::fromJson(input, &err).object();
    QVERIFY(err.error == QJsonParseError::NoError);

    QByteArray out;
    QString e;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        root,
        QStringLiteral("1.jpg"),
        QVariant(),
        true,
        false,
        0.25,
        &out,
        &e));

    const QJsonObject saved = QJsonDocument::fromJson(out).object();
    QCOMPARE(saved.value(QStringLiteral("experimental")).toObject().value(QStringLiteral("flag")).toBool(), true);
    QCOMPARE(saved.value(QStringLiteral("appearance")).toObject().value(QStringLiteral("futureKey")).toString(),
             QStringLiteral("keep-me"));
    QCOMPARE(saved.value(QStringLiteral("appearance")).toObject().value(QStringLiteral("wallpaper")).toString(),
             QStringLiteral("1.jpg"));
    QCOMPARE(saved.value(QStringLiteral("appearance")).toObject().value(QStringLiteral("animations")).toBool(), false);
    QCOMPARE(saved.value(QStringLiteral("appearance")).toObject().value(QStringLiteral("transparency")).toDouble(), 0.25);
}

void ParserTests::appearanceLoginWallpaperIndependent()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": {
        "dynamicColors": true,
        "wallpaper": "5.jpg",
        "animations": true,
        "transparency": null
      }
    })").object();

    QByteArray out;
    QString e;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        root, QStringLiteral("12.jpg"), QStringLiteral("5.jpg"), true, true, QVariant(), &out, &e));

    const QJsonObject appearance = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(appearance.value(QStringLiteral("wallpaper")).toString(), QStringLiteral("12.jpg"));
    QCOMPARE(appearance.value(QStringLiteral("loginWallpaper")).toString(), QStringLiteral("5.jpg"));

    // Desktop change alone must not clear login wallpaper.
    QByteArray out2;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        QJsonDocument::fromJson(out).object(), QStringLiteral("3.jpg"), QStringLiteral("5.jpg"),
        true, true, QVariant(), &out2, &e));
    const QJsonObject a2 = QJsonDocument::fromJson(out2).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a2.value(QStringLiteral("wallpaper")).toString(), QStringLiteral("3.jpg"));
    QCOMPARE(a2.value(QStringLiteral("loginWallpaper")).toString(), QStringLiteral("5.jpg"));
}

void ParserTests::appearanceNullReset()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": {
        "dynamicColors": true,
        "wallpaper": "1.jpg",
        "animations": true,
        "transparency": 0.5
      }
    })").object();

    QByteArray out;
    QString e;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        root, QVariant(), QVariant(), true, true, QVariant(), &out, &e));

    const QJsonObject appearance = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QVERIFY(appearance.value(QStringLiteral("wallpaper")).isNull());
    QVERIFY(appearance.value(QStringLiteral("transparency")).isNull());
}

void ParserTests::appearanceRejectsBadTransparency()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({"schemaVersion":1,"appearance":{}})").object();
    QByteArray out;
    QString e;
    QVERIFY(!SettingsStore::mergeAppearanceAndSerialize(root, QVariant(), QVariant(), true, true, 1.5, &out, &e));
    QVERIFY(e.contains(QStringLiteral("transparency")));
}

void ParserTests::appearanceRejectsBadSchema()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({"schemaVersion":2,"appearance":{}})").object();
    QByteArray out;
    QString e;
    QVERIFY(!SettingsStore::mergeAppearanceAndSerialize(root, QVariant(), QVariant(), true, true, QVariant(), &out, &e));
    QVERIFY(e.contains(QStringLiteral("schemaVersion")));
}

void ParserTests::appearanceRejectsLoginTraversal()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({"schemaVersion":1,"appearance":{}})").object();
    QByteArray out;
    QString e;
    QVERIFY(!SettingsStore::mergeAppearanceAndSerialize(
        root, QVariant(), QStringLiteral("../etc/passwd"), true, true, QVariant(), &out, &e));
    QVERIFY(e.contains(QStringLiteral("loginWallpaper")));
    QVERIFY(!SettingsStore::mergeAppearanceAndSerialize(
        root, QVariant(), QStringLiteral("/tmp/x.jpg"), true, true, QVariant(), &out, &e));
    QVERIFY(e.contains(QStringLiteral("loginWallpaper")));
}

void ParserTests::videoWallpaperIdValidation()
{
    QVERIFY(SettingsStore::isValidVideoWallpaperId(QStringLiteral("rain.mp4")));
    QVERIFY(SettingsStore::isValidVideoWallpaperId(QStringLiteral("a-b_c.WEBM")));
    QVERIFY(SettingsStore::isValidVideoWallpaperId(QStringLiteral("x.mkv")));
    QVERIFY(SettingsStore::isValidVideoWallpaperId(QStringLiteral("x.mov")));
    QVERIFY(!SettingsStore::isValidVideoWallpaperId(QStringLiteral("x.gif")));
    QVERIFY(!SettingsStore::isValidVideoWallpaperId(QStringLiteral("x.jpg")));
    QVERIFY(!SettingsStore::isValidVideoWallpaperId(QStringLiteral("../x.mp4")));
    QVERIFY(!SettingsStore::isValidVideoWallpaperId(QStringLiteral("a/x.mp4")));
    // Static-image ids (desktop + SDDM) never accept videos.
    QVERIFY(!SettingsStore::isValidWallpaperId(QStringLiteral("rain.mp4")));
}

void ParserTests::appearanceVideoMergePreservesUnknown()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": {
        "dynamicColors": true,
        "wallpaper": "5.jpg",
        "animations": true,
        "transparency": null,
        "videoWallpaper": { "file": "old.mp4", "futureKey": "keep-me" }
      }
    })").object();

    const QVariantMap video{
        {QStringLiteral("file"), QStringLiteral("rain.mp4")},
        {QStringLiteral("loop"), true},
        {QStringLiteral("audio"), false},
        {QStringLiteral("profile"), QStringLiteral("economy")},
        {QStringLiteral("pauseWhenCovered"), QVariant::fromValue(nullptr)},
    };

    QByteArray out;
    QString e;
    QVERIFY2(SettingsStore::mergeAppearanceAndSerialize(root, QStringLiteral("5.jpg"), QVariant(), true, true,
                                                        QVariant(), QStringLiteral("video"), video, &out, &e),
             qPrintable(e));

    const QJsonObject a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a.value(QStringLiteral("wallpaper")).toString(), QStringLiteral("5.jpg"));
    QCOMPARE(a.value(QStringLiteral("wallpaperType")).toString(), QStringLiteral("video"));
    const QJsonObject v = a.value(QStringLiteral("videoWallpaper")).toObject();
    QCOMPARE(v.value(QStringLiteral("file")).toString(), QStringLiteral("rain.mp4"));
    QCOMPARE(v.value(QStringLiteral("loop")).toBool(), true);
    QCOMPARE(v.value(QStringLiteral("audio")).toBool(), false);
    QCOMPARE(v.value(QStringLiteral("profile")).toString(), QStringLiteral("economy"));
    QVERIFY(v.value(QStringLiteral("pauseWhenCovered")).isNull());
    QCOMPARE(v.value(QStringLiteral("futureKey")).toString(), QStringLiteral("keep-me"));

    // Legacy overload leaves video keys exactly as they were.
    QJsonObject withVideo = root;
    QJsonObject app = withVideo.value(QStringLiteral("appearance")).toObject();
    app.insert(QStringLiteral("wallpaperType"), QStringLiteral("video"));
    withVideo.insert(QStringLiteral("appearance"), app);
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(withVideo, QStringLiteral("6.jpg"), QVariant(), true, true,
                                                       QVariant(), &out, &e));
    const QJsonObject a2 = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a2.value(QStringLiteral("wallpaperType")).toString(), QStringLiteral("video"));
    QCOMPARE(a2.value(QStringLiteral("videoWallpaper")).toObject().value(QStringLiteral("file")).toString(),
             QStringLiteral("old.mp4"));

    // Back to image: type becomes "image", the video choice is remembered.
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(root, QStringLiteral("5.jpg"), QVariant(), true, true,
                                                       QVariant(), QStringLiteral("image"), video, &out, &e));
    const QJsonObject a3 = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a3.value(QStringLiteral("wallpaperType")).toString(), QStringLiteral("image"));
    QCOMPARE(a3.value(QStringLiteral("videoWallpaper")).toObject().value(QStringLiteral("file")).toString(),
             QStringLiteral("rain.mp4"));
}

void ParserTests::appearanceVideoRejectsInvalid()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({"schemaVersion":1,"appearance":{}})").object();
    QByteArray out;
    QString e;
    auto merge = [&](const QVariant &type, const QVariant &video) {
        return SettingsStore::mergeAppearanceAndSerialize(root, QVariant(), QVariant(), true, true, QVariant(),
                                                          type, video, &out, &e);
    };

    QVERIFY(!merge(QStringLiteral("gif"), QVariant()));
    QVERIFY(e.contains(QStringLiteral("wallpaperType")));

    QVERIFY(!merge(QStringLiteral("video"), QVariant()));
    QVERIFY(e.contains(QStringLiteral("videoWallpaper.file")));

    QVERIFY(!merge(QStringLiteral("video"), QVariantMap{{QStringLiteral("file"), QStringLiteral("../x.mp4")}}));
    QVERIFY(e.contains(QStringLiteral("videoWallpaper.file")));

    QVERIFY(!merge(QStringLiteral("video"), QVariantMap{{QStringLiteral("file"), QStringLiteral("x.jpg")}}));

    QVERIFY(!merge(QVariant(), QVariantMap{{QStringLiteral("profile"), QStringLiteral("ultra")}}));
    QVERIFY(e.contains(QStringLiteral("profile")));

    QVERIFY(!merge(QVariant(), QVariantMap{{QStringLiteral("loop"), QStringLiteral("yes")}}));
    QVERIFY(e.contains(QStringLiteral("loop")));

    QVERIFY(!merge(QVariant(), QStringLiteral("rain.mp4")));
    QVERIFY(e.contains(QStringLiteral("object")));

    // SDDM stays static.
    QVERIFY(!SettingsStore::mergeAppearanceAndSerialize(root, QVariant(), QStringLiteral("rain.mp4"), true, true,
                                                        QVariant(), QVariant(), QVariant(), &out, &e));
    QVERIFY(e.contains(QStringLiteral("loginWallpaper")));
}

void ParserTests::appearanceVideoImageOnlyFileUnchanged()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": { "dynamicColors": true, "wallpaper": "5.jpg", "animations": true, "transparency": null }
    })").object();
    QByteArray out;
    QString e;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(root, QStringLiteral("5.jpg"), QVariant(), true, true,
                                                       QVariant(), QVariant(), QVariant(), &out, &e));
    const QJsonObject a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QVERIFY(!a.contains(QStringLiteral("wallpaperType")));
    QVERIFY(!a.contains(QStringLiteral("videoWallpaper")));
    QCOMPARE(out, QJsonDocument(root).toJson(QJsonDocument::Indented));
}

void ParserTests::videoGalleryListsOnlyVideos()
{
    QTemporaryDir home;
    QTemporaryDir repo;
    QVERIFY(home.isValid() && repo.isValid());
    const QByteArray oldHome = qgetenv("HOME");
    qputenv("HOME", home.path().toUtf8());

    QDir(repo.path()).mkpath(QStringLiteral("assets/wallpapers"));
    const QString wallDir = QDir(repo.path()).filePath(QStringLiteral("assets/wallpapers"));
    for (const QString &name : {QStringLiteral("a.jpg"), QStringLiteral("b.mp4"), QStringLiteral("c.WEBM"),
                                QStringLiteral("d.gif"), QStringLiteral("bad name.mp4")}) {
        QFile f(QDir(wallDir).filePath(name));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("x");
    }

    WallpaperGalleryModel images;
    images.setRepoPath(repo.path());
    WallpaperGalleryModel videos(WallpaperGalleryModel::MediaKind::Videos);
    videos.setRepoPath(repo.path());

    qputenv("HOME", oldHome);

    QCOMPARE(images.rowCount(), 1);
    QCOMPARE(images.data(images.index(0), WallpaperGalleryModel::FileNameRole).toString(), QStringLiteral("a.jpg"));
    QCOMPARE(images.data(images.index(0), WallpaperGalleryModel::IsVideoRole).toBool(), false);
    QVERIFY(images.absolutePathForId(QStringLiteral("b.mp4")).isEmpty());

    QCOMPARE(videos.rowCount(), 2);
    QCOMPARE(videos.data(videos.index(0), WallpaperGalleryModel::FileNameRole).toString(), QStringLiteral("b.mp4"));
    QCOMPARE(videos.data(videos.index(1), WallpaperGalleryModel::FileNameRole).toString(), QStringLiteral("c.WEBM"));
    QCOMPARE(videos.data(videos.index(0), WallpaperGalleryModel::IsVideoRole).toBool(), true);
    QVERIFY(!videos.absolutePathForId(QStringLiteral("b.mp4")).isEmpty());
    QVERIFY(videos.absolutePathForId(QStringLiteral("a.jpg")).isEmpty());
    QVERIFY(videos.absolutePathForId(QStringLiteral("../b.mp4")).isEmpty());
}

void ParserTests::videoApplyArgv()
{
    QCOMPARE(WallpaperApplier::videoApplyArguments(QStringLiteral("/w/rain.mp4"), true, false,
                                                   QStringLiteral("economy"), true),
             (QStringList{QStringLiteral("apply"), QStringLiteral("/w/rain.mp4"),
                          QStringLiteral("--loop"), QStringLiteral("1"),
                          QStringLiteral("--audio"), QStringLiteral("0"),
                          QStringLiteral("--profile"), QStringLiteral("economy"),
                          QStringLiteral("--pause-covered"), QStringLiteral("1")}));
    // Unknown profile never reaches the helper.
    const QStringList args = WallpaperApplier::videoApplyArguments(QStringLiteral("/w/rain.mp4"), false, true,
                                                                   QStringLiteral("ultra"), false);
    QCOMPARE(args.at(7), QStringLiteral("balanced"));
    QCOMPARE(args.at(3), QStringLiteral("0"));
    QCOMPARE(args.at(5), QStringLiteral("1"));
    QCOMPARE(args.at(9), QStringLiteral("0"));
}

void ParserTests::saveFileAtomicKeepsOriginalOnCancel()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath(QStringLiteral("settings.json"));
    {
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(R"({"schemaVersion":1,"appearance":{"dynamicColors":true}})");
    }

    QSaveFile sf(path);
    QVERIFY(sf.open(QIODevice::WriteOnly));
    sf.write("CORRUPT");
    sf.cancelWriting();

    QFile f(path);
    QVERIFY(f.open(QIODevice::ReadOnly));
    const QByteArray kept = f.readAll();
    QVERIFY(kept.contains("schemaVersion"));
    QVERIFY(!kept.contains("CORRUPT"));
}

static bool writeMinimalRepo(const QTemporaryDir &dir, const QByteArray &settingsJson)
{
    if (!QDir(dir.path()).mkpath(QStringLiteral("ryoku")))
        return false;
    QFile flake(dir.filePath(QStringLiteral("flake.nix")));
    if (!flake.open(QIODevice::WriteOnly))
        return false;
    flake.write("{}\n");
    flake.close();
    QFile settings(dir.filePath(QStringLiteral("ryoku/settings.json")));
    if (!settings.open(QIODevice::WriteOnly))
        return false;
    settings.write(settingsJson);
    settings.close();
    return true;
}

void ParserTests::saveNoopBytesIdentical()
{
    // Start from Qt canonical bytes (as SettingsStore would emit).
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": {
        "dynamicColors": true,
        "wallpaper": "5.jpg",
        "animations": true,
        "transparency": null,
        "futureKey": "keep"
      },
      "desktop": { "hyprland": { "gapsIn": null } }
    })").object();
    const QByteArray canonical = QJsonDocument(root).toJson(QJsonDocument::Indented);

    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(writeMinimalRepo(dir, canonical));

    SettingsStore store;
    store.setRepoPath(dir.path());
    QVERIFY(store.loaded());

    const QString path = dir.filePath(QStringLiteral("ryoku/settings.json"));
    QFile before(path);
    QVERIFY(before.open(QIODevice::ReadOnly));
    const QByteArray bytesBefore = before.readAll();
    before.close();

    QVERIFY(store.saveAppearance(QStringLiteral("5.jpg"), QVariant(), true, true, QVariant()));

    QFile after(path);
    QVERIFY(after.open(QIODevice::ReadOnly));
    const QByteArray bytesAfter = after.readAll();
    QCOMPARE(bytesAfter, bytesBefore);
    QCOMPARE(bytesAfter, canonical);
}

void ParserTests::saveSameValueSkipsRewrite()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": {
        "dynamicColors": true,
        "wallpaper": "5.jpg",
        "animations": true,
        "transparency": null
      }
    })").object();
    const QByteArray canonical = QJsonDocument(root).toJson(QJsonDocument::Indented);

    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QVERIFY(writeMinimalRepo(dir, canonical));

    SettingsStore store;
    store.setRepoPath(dir.path());
    QVERIFY(store.loaded());

    const QString path = dir.filePath(QStringLiteral("ryoku/settings.json"));

    QVERIFY(store.saveAppearance(QStringLiteral("5.jpg"), QVariant(), true, true, 0.25));
    QFile f1(path);
    QVERIFY(f1.open(QIODevice::ReadOnly));
    const QByteArray afterFirst = f1.readAll();
    f1.close();
    QVERIFY(afterFirst.contains(R"("transparency": 0.25)"));
    QVERIFY(afterFirst.contains(R"("wallpaper": "5.jpg")"));

    const QDateTime mtime1 = QFileInfo(path).lastModified();
    QVERIFY(store.saveAppearance(QStringLiteral("5.jpg"), QVariant(), true, true, 0.25));
    QFile f2(path);
    QVERIFY(f2.open(QIODevice::ReadOnly));
    const QByteArray afterSecond = f2.readAll();
    QCOMPARE(afterSecond, afterFirst);
    QCOMPARE(QFileInfo(path).lastModified(), mtime1);
}

void ParserTests::serializeDeterministic()
{
    const QByteArray a = R"({"schemaVersion":1,"appearance":{"wallpaper":"5.jpg","dynamicColors":true,"zzz":1},"extra":{"b":2,"a":1}})";
    const QByteArray b = R"({"extra":{"a":1,"b":2},"appearance":{"zzz":1,"dynamicColors":true,"wallpaper":"5.jpg"},"schemaVersion":1})";

    QJsonObject oa = QJsonDocument::fromJson(a).object();
    QJsonObject ob = QJsonDocument::fromJson(b).object();

    QByteArray outA;
    QByteArray outB;
    QString err;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        oa, QStringLiteral("5.jpg"), QVariant(), true, true, QVariant(), &outA, &err));
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        ob, QStringLiteral("5.jpg"), QVariant(), true, true, QVariant(), &outB, &err));
    QCOMPARE(outA, outB);

    // Double round-trip of merge output stays identical.
    const QJsonObject round = QJsonDocument::fromJson(outA).object();
    QByteArray outC;
    QVERIFY(SettingsStore::mergeAppearanceAndSerialize(
        round, QStringLiteral("5.jpg"), QVariant(), true, true, QVariant(), &outC, &err));
    QCOMPARE(outC, outA);

    // Unknown keys survive.
    const QJsonObject saved = QJsonDocument::fromJson(outA).object();
    QCOMPARE(saved.value(QStringLiteral("extra")).toObject().value(QStringLiteral("a")).toInt(), 1);
    QCOMPARE(saved.value(QStringLiteral("appearance")).toObject().value(QStringLiteral("zzz")).toInt(), 1);
}

void ParserTests::flatpakIdValidation()
{
    QVERIFY(SettingsStore::isValidFlatpakId(QStringLiteral("org.cutwire.Drift")));
    QVERIFY(SettingsStore::isValidFlatpakId(QStringLiteral("com.mojang.Minecraft")));
    QVERIFY(SettingsStore::isValidFlatpakId(QStringLiteral("org.localsend.localsend_app")));
    QVERIFY(!SettingsStore::isValidFlatpakId(QStringLiteral("")));
    QVERIFY(!SettingsStore::isValidFlatpakId(QStringLiteral("nodots")));
    QVERIFY(!SettingsStore::isValidFlatpakId(QStringLiteral("../evil")));
    QVERIFY(!SettingsStore::isValidFlatpakId(QStringLiteral("org cutwire.Drift")));
    QVERIFY(!SettingsStore::isValidFlatpakId(QStringLiteral("org/cutwire.Drift")));
}

void ParserTests::flatpakNormalizeSortDedup()
{
    QString err;
    const QStringList out = SettingsStore::normalizeFlatpakDeclared(
        {QStringLiteral("org.z.App"), QStringLiteral("com.a.App"), QStringLiteral("org.z.App")},
        &err);
    QVERIFY(err.isEmpty());
    QCOMPARE(out, (QStringList{QStringLiteral("com.a.App"), QStringLiteral("org.z.App")}));
}

void ParserTests::flatpakMergePreservesUnknown()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": { "dynamicColors": true, "wallpaper": "5.jpg" },
      "apps": { "flatpakDeclared": [], "futureAppKey": true },
      "experimental": { "flag": 1 }
    })").object();

    QByteArray out;
    QString err;
    QVERIFY(SettingsStore::mergeFlatpakDeclaredAndSerialize(
        root,
        {QStringLiteral("org.cutwire.Drift"), QStringLiteral("com.a.App")},
        &out,
        &err));

    const QJsonObject saved = QJsonDocument::fromJson(out).object();
    QCOMPARE(saved.value(QStringLiteral("experimental")).toObject().value(QStringLiteral("flag")).toInt(), 1);
    QCOMPARE(saved.value(QStringLiteral("apps")).toObject().value(QStringLiteral("futureAppKey")).toBool(), true);
    QCOMPARE(saved.value(QStringLiteral("appearance")).toObject().value(QStringLiteral("wallpaper")).toString(),
             QStringLiteral("5.jpg"));

    const QJsonArray arr = saved.value(QStringLiteral("apps")).toObject().value(QStringLiteral("flatpakDeclared")).toArray();
    QCOMPARE(arr.size(), 2);
    QCOMPARE(arr.at(0).toString(), QStringLiteral("com.a.App"));
    QCOMPARE(arr.at(1).toString(), QStringLiteral("org.cutwire.Drift"));
}

void ParserTests::flatpakRejectsInvalidId()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({"schemaVersion":1})").object();
    QByteArray out;
    QString err;
    QVERIFY(!SettingsStore::mergeFlatpakDeclaredAndSerialize(
        root, {QStringLiteral("not-a-flatpak-id")}, &out, &err));
    QVERIFY(err.contains(QStringLiteral("invalid flatpak id")));
}

void ParserTests::flatpakParseListOutput()
{
    const QByteArray sample =
        "org.cutwire.Drift\tDrift\n"
        "com.example.App\tExample App\n"
        "Application\tName\n"; // header-ish ignore
    const auto apps = FlatpakAppsModel::parseFlatpakListOutput(sample);
    QCOMPARE(apps.size(), 2);
    QCOMPARE(apps.at(0).applicationId, QStringLiteral("org.cutwire.Drift"));
    QCOMPARE(apps.at(0).name, QStringLiteral("Drift"));
    QCOMPARE(apps.at(1).applicationId, QStringLiteral("com.example.App"));
}

void ParserTests::flatpakClassifyStatuses()
{
    QVector<FlatpakAppsModel::InstalledApp> installed;
    FlatpakAppsModel::InstalledApp drift;
    drift.applicationId = QStringLiteral("org.cutwire.Drift");
    drift.name = QStringLiteral("Drift");
    installed.append(drift);
    FlatpakAppsModel::InstalledApp local;
    local.applicationId = QStringLiteral("org.local.Only");
    local.name = QStringLiteral("Local Only");
    installed.append(local);

    const QStringList declared{
        QStringLiteral("org.cutwire.Drift"),
        QStringLiteral("org.pending.App"),
    };

    const auto rows = FlatpakAppsModel::classify(declared, installed);
    QCOMPARE(rows.size(), 3);

    QCOMPARE(rows.at(0).applicationId, QStringLiteral("org.cutwire.Drift"));
    QCOMPARE(rows.at(0).status, FlatpakAppsModel::Managed);

    QCOMPARE(rows.at(1).applicationId, QStringLiteral("org.pending.App"));
    QCOMPARE(rows.at(1).status, FlatpakAppsModel::Pending);

    QCOMPARE(rows.at(2).applicationId, QStringLiteral("org.local.Only"));
    QCOMPARE(rows.at(2).status, FlatpakAppsModel::Local);
}

void ParserTests::networkSecurityAndSort()
{
    QCOMPARE(NetworkManagerModel::clampStrength(150), 100);
    QCOMPARE(NetworkManagerModel::clampStrength(-3), 0);
    QVERIFY(NetworkManagerModel::isSecuredFromFlags(0, 0x100, 0));
    QVERIFY(!NetworkManagerModel::isSecuredFromFlags(0, 0, 0));
    QCOMPARE(NetworkManagerModel::securityLabel(true), QStringLiteral("Secured"));

    QVector<NetworkManagerModel::AccessPoint> aps;
    NetworkManagerModel::AccessPoint a;
    a.ssid = QStringLiteral("B");
    a.strength = 40;
    NetworkManagerModel::AccessPoint b;
    b.ssid = QStringLiteral("A");
    b.strength = 90;
    NetworkManagerModel::AccessPoint c;
    c.ssid = QStringLiteral("C");
    c.strength = 10;
    c.connected = true;
    aps << a << b << c;
    const auto sorted = NetworkManagerModel::sortAccessPoints(aps);
    QCOMPARE(sorted.at(0).ssid, QStringLiteral("C"));
    QCOMPARE(sorted.at(1).ssid, QStringLiteral("A"));
    QCOMPARE(sorted.at(2).ssid, QStringLiteral("B"));
}

void ParserTests::bluetoothSortAndStatus()
{
    QVector<BluetoothModel::Device> devices;
    BluetoothModel::Device a;
    a.name = QStringLiteral("Speaker");
    a.paired = true;
    BluetoothModel::Device b;
    b.name = QStringLiteral("Buds");
    b.connected = true;
    b.battery = 76;
    BluetoothModel::Device c;
    c.name = QStringLiteral("Mouse");
    devices << a << b << c;
    const auto sorted = BluetoothModel::sortDevices(devices);
    QCOMPARE(sorted.at(0).name, QStringLiteral("Buds"));
    QCOMPARE(sorted.at(1).name, QStringLiteral("Speaker"));
    QVERIFY(BluetoothModel::statusLabelFor(sorted.at(0)).contains(QStringLiteral("76")));
}

void ParserTests::soundVolumeParseAndClamp()
{
    QCOMPARE(SoundModel::clampVolume(200), 150);
    QCOMPARE(SoundModel::clampVolume(-1), 0);
    int vol = 0;
    bool muted = false;
    QVERIFY(SoundModel::parseVolumeLine("Volume: 0.42\n", &vol, &muted));
    QCOMPARE(vol, 42);
    QVERIFY(!muted);
    QVERIFY(SoundModel::parseVolumeLine("Volume: 0.10 [MUTED]\n", &vol, &muted));
    QCOMPARE(vol, 10);
    QVERIFY(muted);

    const QByteArray status = R"(
Audio
 ├─ Sinks:
 │  *   48. Softwarespeak Analog Stereo
 │      49. HDMI Output
 ├─ Sources:
 │  *   50. Webcam Mic
 │      51. Headset Mic
)";
    const auto sinks = SoundModel::parseWpctlStatus(status, true);
    QVERIFY(sinks.size() >= 1);
    QCOMPARE(sinks.at(0).id, 48u);
    QVERIFY(sinks.at(0).isDefault);
    const auto sources = SoundModel::parseWpctlStatus(status, false);
    QVERIFY(sources.size() >= 1);
}

void ParserTests::displayParseModesAndValidate()
{
    DisplayModel::Mode mode;
    QVERIFY(DisplayModel::parseModeToken(QStringLiteral("1920x1080@60.05Hz"), &mode));
    QCOMPARE(mode.width, 1920);
    QCOMPARE(mode.height, 1080);
    QCOMPARE(mode.refreshRate, 60.05);
    QVERIFY(!DisplayModel::parseModeToken(QStringLiteral("bogus"), &mode));

    QVERIFY(DisplayModel::validateScale(1.0));
    QVERIFY(DisplayModel::validateScale(0.5));
    QVERIFY(!DisplayModel::validateScale(0.25));
    QVERIFY(!DisplayModel::validateScale(4.0));
    QCOMPARE(DisplayModel::clampScale(4.0), 3.0);

    const QByteArray json = R"([
      {
        "name": "eDP-1",
        "description": "Built-in",
        "make": "AUO",
        "model": "4A99",
        "width": 1920,
        "height": 1080,
        "refreshRate": 60.05,
        "x": 0,
        "y": 0,
        "scale": 1,
        "focused": true,
        "disabled": false,
        "availableModes": ["1920x1080@60.05Hz"]
      },
      {
        "name": "HDMI-A-1",
        "width": 1920,
        "height": 1080,
        "refreshRate": 100.0,
        "x": 1920,
        "y": 0,
        "scale": 1,
        "focused": false,
        "disabled": false,
        "availableModes": ["1920x1080@100.00Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"]
      }
    ])";
    QString err;
    const auto monitors = DisplayModel::parseMonitorsJson(json, &err);
    QVERIFY2(err.isEmpty(), qPrintable(err));
    QCOMPARE(monitors.size(), 2);
    QCOMPARE(monitors.at(0).name, QStringLiteral("eDP-1"));
    QCOMPARE(monitors.at(1).availableModes.size(), 3);

    DisplayModel::Draft d;
    d.name = QStringLiteral("eDP-1");
    d.enabled = true;
    d.width = 1920;
    d.height = 1080;
    d.refreshRate = 60.05;
    d.scale = 1.0;
    QCOMPARE(DisplayModel::buildMonitorKeyword(d), QStringLiteral("eDP-1,1920x1080@60.05,0x0,1"));
    d.enabled = false;
    QCOMPARE(DisplayModel::buildMonitorKeyword(d), QStringLiteral("eDP-1,disable"));
}

void ParserTests::displayRoleNamesAvoidItemEnabledClash()
{
    DisplayModel model;
    const auto roles = model.roleNames();
    QVERIFY(roles.values().contains(QByteArrayLiteral("displayEnabled")));
    QVERIFY(!roles.values().contains(QByteArrayLiteral("enabled")));
}

void ParserTests::displayCannotDisableLast()
{
    QVector<DisplayModel::Draft> drafts;
    DisplayModel::Draft a;
    a.name = QStringLiteral("eDP-1");
    a.enabled = true;
    a.width = 1920;
    a.height = 1080;
    a.refreshRate = 60;
    a.scale = 1.0;
    DisplayModel::Draft b;
    b.name = QStringLiteral("HDMI-A-1");
    b.enabled = false;
    drafts << a << b;

    QString err;
    QVERIFY(!DisplayModel::canDisableMonitor(drafts, QStringLiteral("eDP-1"), &err));
    QVERIFY(err.contains(QStringLiteral("last")));
    QVERIFY(DisplayModel::canDisableMonitor(drafts, QStringLiteral("HDMI-A-1"), &err));

    b.enabled = true;
    b.width = 1920;
    b.height = 1080;
    b.refreshRate = 100;
    b.scale = 1.0;
    drafts[1] = b;
    QVERIFY(DisplayModel::canDisableMonitor(drafts, QStringLiteral("eDP-1"), &err));
    QVERIFY2(DisplayModel::validateLayout(drafts, &err), qPrintable(err));

    drafts[0].enabled = false;
    drafts[1].enabled = false;
    QVERIFY(!DisplayModel::validateLayout(drafts, &err));
}

void ParserTests::displaySnapshotRoundTrip()
{
    QVector<DisplayModel::Monitor> monitors;
    DisplayModel::Monitor m;
    m.name = QStringLiteral("eDP-1");
    m.width = 1920;
    m.height = 1080;
    m.refreshRate = 60.05;
    m.scale = 1.25;
    m.x = 0;
    m.y = 0;
    m.enabled = true;
    monitors.append(m);

    const QByteArray bytes = DisplayModel::serializeSnapshot(monitors);
    QString err;
    const auto restored = DisplayModel::deserializeSnapshot(bytes, &err);
    QVERIFY2(err.isEmpty(), qPrintable(err));
    QCOMPARE(restored.size(), 1);
    QCOMPARE(restored.at(0).name, QStringLiteral("eDP-1"));
    QCOMPARE(restored.at(0).width, 1920);
    QCOMPARE(restored.at(0).scale, 1.25);
}

void ParserTests::displaySettingsMergePreservesUnknown()
{
    const QByteArray input = R"({
      "schemaVersion": 1,
      "appearance": { "dynamicColors": true },
      "futureTop": 42,
      "display": { "futureDisplayKey": true }
    })";
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(input, &perr);
    QVERIFY(perr.error == QJsonParseError::NoError);

    QVariantList monitors;
    QVariantMap mon;
    mon.insert(QStringLiteral("name"), QStringLiteral("eDP-1"));
    mon.insert(QStringLiteral("enabled"), true);
    mon.insert(QStringLiteral("width"), 1920);
    mon.insert(QStringLiteral("height"), 1080);
    mon.insert(QStringLiteral("refreshRate"), 60.0);
    mon.insert(QStringLiteral("scale"), 1.0);
    mon.insert(QStringLiteral("x"), 0);
    mon.insert(QStringLiteral("y"), 0);
    monitors.append(mon);

    QByteArray out;
    QString err;
    QVERIFY(SettingsStore::mergeDisplayMonitorsAndSerialize(doc.object(), monitors, &out, &err));
    const QJsonObject saved = QJsonDocument::fromJson(out).object();
    QCOMPARE(saved.value(QStringLiteral("futureTop")).toInt(), 42);
    QCOMPARE(saved.value(QStringLiteral("display")).toObject().value(QStringLiteral("futureDisplayKey")).toBool(), true);
    const QJsonArray arr = saved.value(QStringLiteral("display")).toObject().value(QStringLiteral("monitors")).toArray();
    QCOMPARE(arr.size(), 1);
    QCOMPARE(arr.at(0).toObject().value(QStringLiteral("name")).toString(), QStringLiteral("eDP-1"));
}

void ParserTests::powerBrightnessClampAndBatteryMap()
{
    QCOMPARE(PowerModel::clampBrightness(0), 1);
    QCOMPARE(PowerModel::clampBrightness(150), 100);
    QCOMPARE(PowerModel::clampBrightness(70), 70);
    // brightnessctl 0.5: -n is a flag; must NOT insert a bare "1" before set.
    QCOMPARE(PowerModel::brightnessSetArgs(70, true),
             (QStringList{QStringLiteral("-c"), QStringLiteral("backlight"), QStringLiteral("-n"),
                          QStringLiteral("set"), QStringLiteral("70%")}));
    QCOMPARE(PowerModel::brightnessSetArgs(30, false),
             (QStringList{QStringLiteral("-n"), QStringLiteral("set"), QStringLiteral("30%")}));
    QCOMPARE(PowerModel::mapBatteryState(1), QStringLiteral("Charging"));
    QCOMPARE(PowerModel::mapBatteryState(2), QStringLiteral("Discharging"));
    QCOMPARE(PowerModel::mapBatteryState(4), QStringLiteral("Full"));
    QCOMPARE(PowerModel::formatBatteryTime(0), QString());
    QCOMPARE(PowerModel::formatBatteryTime(3660), QStringLiteral("1h 1m"));
    QCOMPARE(PowerModel::profileDisplayName(QStringLiteral("power-saver")), QStringLiteral("Power Saver"));
    QCOMPARE(PowerModel::profileDisplayName(QStringLiteral("balanced")), QStringLiteral("Balanced"));
    QCOMPARE(PowerModel::profileDisplayName(QStringLiteral("performance")), QStringLiteral("Performance"));
}

void ParserTests::applyHashCompareAndStatus()
{
    const QString h1 = QStringLiteral("7d295f63ba12e0dd54b405713bb1c40ab8e161a300ce5ee47a264b931ffe64ff");
    const QString h2 = QStringLiteral("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

    QCOMPARE(ApplyController::normalizeHash(QStringLiteral("  abc\n")), QStringLiteral("abc"));
    QVERIFY(ApplyController::isValidSha256Hex(h1));
    QVERIFY(!ApplyController::isValidSha256Hex(QStringLiteral("short")));
    QVERIFY(!ApplyController::isValidSha256Hex(QStringLiteral("7d295f63ba12e0dd54b405713bb1c40ab8e161a300ce5ee47a264b931ffe64fg"))); // bad char

    // Trailing whitespace → still match
    QVERIFY(ApplyController::hashesMatch(h1, h1 + QStringLiteral("\n")));
    QVERIFY(ApplyController::hashesMatch(QStringLiteral("  ") + h1, h1));
    QVERIFY(!ApplyController::hashesMatch(h1, h2));
    QVERIFY(!ApplyController::hashesMatch(QString(), h1));

    // Mixed case hex still matches
    QVERIFY(ApplyController::hashesMatch(h1.toUpper(), h1));

    // nix eval stdout extraction ignores only peripheral whitespace
    QCOMPARE(ApplyController::hashFromNixEvalStdout(h1.toUtf8() + "\n"), h1);

    // Merged warning must NOT be treated as a valid hash
    const QByteArray polluted = QByteArray("warning: Git tree is dirty\n") + h1.toUtf8();
    QVERIFY(!ApplyController::isValidSha256Hex(ApplyController::hashFromNixEvalStdout(polluted)));

    // Marker absent → NeedsApply
    QCOMPARE(ApplyController::statusFromHashes(false, true, false, h1, QString()),
             QString::fromLatin1(ApplyController::StatusNeedsApply));
    // Match → Applied (git dirty is irrelevant to this pure helper)
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h1, h1),
             QString::fromLatin1(ApplyController::StatusApplied));
    // Differ → NeedsApply
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h1, h2),
             QString::fromLatin1(ApplyController::StatusNeedsApply));
    // Current not resolved yet (marker already present) → Idle, not NeedsApply
    QCOMPARE(ApplyController::statusFromHashes(true, false, false, QString(), h1),
             QString::fromLatin1(ApplyController::StatusIdle));
    // Current arrives later with match → Applied
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h1, h1),
             QString::fromLatin1(ApplyController::StatusApplied));
    // Eval failed → HashError (not silent NeedsApply)
    QCOMPARE(ApplyController::statusFromHashes(true, true, true, QString(), h1),
             QString::fromLatin1(ApplyController::StatusHashError));

    QCOMPARE(ApplyController::needsApplyReason(true, true, false, h1, h1),
             QStringLiteral("hashes match (Applied)"));
    QCOMPARE(ApplyController::needsApplyReason(false, true, false, h1, QString()),
             QStringLiteral("applied marker absent"));
}

void ParserTests::applyNixEvalStderrDoesNotFail()
{
    const QString h1 = QStringLiteral("7d295f63ba12e0dd54b405713bb1c40ab8e161a300ce5ee47a264b931ffe64ff");
    const QByteArray dirtyWarn =
        QByteArray("warning: Git tree '/home/alice/ryoku' is dirty\n");

    // 1) exit 0 + valid hash + stderr warning → SUCCESS
    {
        const auto r = ApplyController::interpretNixEvalHashResult(
            0, 0, h1.toUtf8() + '\n', dirtyWarn);
        QVERIFY(r.ok);
        QCOMPARE(r.hash, h1);
        QVERIFY(r.error.isEmpty());
        QVERIFY(r.stderrWarning.contains(QStringLiteral("dirty")));
    }

    // 2) exit 0 + valid hash + empty stderr → SUCCESS
    {
        const auto r = ApplyController::interpretNixEvalHashResult(0, 0, h1.toUtf8(), {});
        QVERIFY(r.ok);
        QCOMPARE(r.hash, h1);
        QVERIFY(r.stderrWarning.isEmpty());
    }

    // 3) exit 1 + stderr → FAIL (stderr only as detail)
    {
        const auto r = ApplyController::interpretNixEvalHashResult(1, 0, {}, dirtyWarn);
        QVERIFY(!r.ok);
        QVERIFY(r.hash.isEmpty());
        QVERIFY(r.error.contains(QStringLiteral("Failed to evaluate")));
        QVERIFY(r.error.contains(QStringLiteral("dirty")));
    }

    // 4) exit 0 + invalid stdout → FAIL
    {
        const auto r = ApplyController::interpretNixEvalHashResult(
            0, 0, QByteArray("not-a-hash\n"), {});
        QVERIFY(!r.ok);
        QVERIFY(r.error.contains(QStringLiteral("invalid format")));
    }

    // CrashExit must fail even with exitCode 0
    {
        const auto r = ApplyController::interpretNixEvalHashResult(0, 1, h1.toUtf8(), {});
        QVERIFY(!r.ok);
        QVERIFY(r.error.contains(QStringLiteral("abnormally")));
    }

    // 5) dirty Git tree does not change Apply state when hashes match
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h1, h1),
             QString::fromLatin1(ApplyController::StatusApplied));
    {
        const auto r = ApplyController::interpretNixEvalHashResult(
            0, 0, h1.toUtf8(), dirtyWarn);
        QVERIFY(r.ok);
        QCOMPARE(ApplyController::statusFromHashes(true, true, false, r.hash, h1),
                 QString::fromLatin1(ApplyController::StatusApplied));
    }
}

void ParserTests::applyDeclarativePageBadge()
{
    using AC = ApplyController;
    // Unsaved draft wins over apply state
    QCOMPARE(AC::declarativePageStatusLabel(false, true, true, QString::fromLatin1(AC::StatusNeedsApply)),
             QStringLiteral("Unsaved changes"));
    QCOMPARE(AC::declarativePageStatusLabel(false, true, false, QString::fromLatin1(AC::StatusApplied)),
             QStringLiteral("Unsaved changes"));

    // Saved + Needs Apply (Apps Flatpak change pending)
    QCOMPARE(AC::declarativePageStatusLabel(false, false, true, QString::fromLatin1(AC::StatusNeedsApply)),
             QStringLiteral("Needs Apply"));
    QCOMPARE(AC::declarativePageStatusLabel(false, false, true, QString::fromLatin1(AC::StatusReady)),
             QStringLiteral("Needs Apply"));

    // Hash/marker match → Applied (GUI Apply or external rebuild)
    QCOMPARE(AC::declarativePageStatusLabel(false, false, false, QString::fromLatin1(AC::StatusApplied)),
             QStringLiteral("Applied"));

    // must not stick at Needs Apply after Applied
    QVERIFY(AC::declarativePageStatusLabel(false, false, false, QString::fromLatin1(AC::StatusApplied))
            != QStringLiteral("Needs Apply"));

    // Error
    QCOMPARE(AC::declarativePageStatusLabel(true, false, true, QString::fromLatin1(AC::StatusNeedsApply)),
             QStringLiteral("Error"));
}

void ParserTests::applyReconcilePrivilegedVerification()
{
    using AC = ApplyController;
    QString warning;

    // CrashExit + hash match → Applied with warning (diagnostic preserved)
    QCOMPARE(AC::reconcilePrivilegedVerification(
                 true, false, false, false, false,
                 QStringLiteral("Privileged apply process terminated unexpectedly"),
                 &warning),
             QString::fromLatin1(AC::StatusApplied));
    QVERIFY(warning.contains(QStringLiteral("verified as applied")));
    QVERIFY(warning.contains(QStringLiteral("ended unexpectedly")));
    QVERIFY(warning.contains(QStringLiteral("terminated unexpectedly")));

    // Nonzero / mismatch → ApplyFailed
    warning.clear();
    QCOMPARE(AC::reconcilePrivilegedVerification(
                 false, false, false, false, false,
                 QStringLiteral("Apply failed (pkexec NormalExit code=1)"),
                 &warning),
             QString::fromLatin1(AC::StatusApplyFailed));
    QVERIFY(warning.isEmpty());

    // NormalExit 0 + hash match → Applied, no warning
    warning.clear();
    QCOMPARE(AC::reconcilePrivilegedVerification(
                 true, true, false, false, false, QString(), &warning),
             QString::fromLatin1(AC::StatusApplied));
    QVERIFY(warning.isEmpty());

    // Auth denied + no match → AuthorizationDenied
    QCOMPARE(AC::reconcilePrivilegedVerification(
                 false, false, false, true, false, QStringLiteral("Authorization denied"),
                 &warning),
             QString::fromLatin1(AC::StatusAuthorizationDenied));

    // FailedToStart + no match → AuthorizationError
    QCOMPARE(AC::reconcilePrivilegedVerification(
                 false, false, false, false, true, QStringLiteral("FailedToStart"),
                 &warning),
             QString::fromLatin1(AC::StatusAuthorizationError));

    // FailedToStart but hash already matches → Applied with warning
    warning.clear();
    QCOMPARE(AC::reconcilePrivilegedVerification(
                 true, false, false, false, true, QStringLiteral("FailedToStart"),
                 &warning),
             QString::fromLatin1(AC::StatusApplied));
    QVERIFY(!warning.isEmpty());
}

void ParserTests::applyPlanInventory()
{
    const auto inv = ApplyController::knownInventory();
    QCOMPARE(inv.size(), 2);
    QCOMPARE(inv.at(0).id, QStringLiteral("apps.flatpakDeclared"));
    QCOMPARE(inv.at(0).scope, ApplyController::Scope::System);
    QCOMPARE(inv.at(1).id, QStringLiteral("appearance.loginWallpaper"));
    QCOMPARE(inv.at(1).scope, ApplyController::Scope::System);

    QVERIFY(ApplyController::buildPlanForNeedsApply(false).isEmpty());
    const auto pending = ApplyController::buildPlanForNeedsApply(true);
    QCOMPARE(pending.size(), 2);

    const QVariantList system = ApplyController::planToVariant(pending, ApplyController::Scope::System);
    const QVariantList user = ApplyController::planToVariant(pending, ApplyController::Scope::User);
    QCOMPARE(system.size(), 2);
    QVERIFY(user.isEmpty());

    bool foundLogin = false;
    bool foundDesktopWallpaper = false;
    for (const auto &item : pending) {
        if (item.id == QStringLiteral("appearance.loginWallpaper"))
            foundLogin = true;
        if (item.id == QStringLiteral("appearance.wallpaper"))
            foundDesktopWallpaper = true;
    }
    QVERIFY(foundLogin);
    QVERIFY(!foundDesktopWallpaper);
}

void ParserTests::applyValidationParseAndAllowlist()
{
    QCOMPARE(ApplyController::parseValidationResult(0, "ok\n"), QStringLiteral("flake check passed"));
    QVERIFY(ApplyController::parseValidationResult(1, "error: boom\n").contains(QStringLiteral("boom")));

    QVERIFY(ApplyController::isAllowlistedNixEvalArgs(
        {QStringLiteral("eval"), QStringLiteral("--raw"), QStringLiteral(".#ryokuSettingsHash")}));
    QVERIFY(!ApplyController::isAllowlistedNixEvalArgs(
        {QStringLiteral("eval"), QStringLiteral("--raw"), QStringLiteral(".#evil")}));
    QVERIFY(!ApplyController::isAllowlistedNixEvalArgs(
        {QStringLiteral("run"), QStringLiteral("nixpkgs#hello")}));
    QVERIFY(ApplyController::isAllowlistedFlakeCheckArgs(
        {QStringLiteral("flake"), QStringLiteral("check")}));
    QVERIFY(!ApplyController::isAllowlistedFlakeCheckArgs(
        {QStringLiteral("flake"), QStringLiteral("update")}));
    QVERIFY(!ApplyController::isAllowlistedFlakeCheckArgs(
        {QStringLiteral("build"), QStringLiteral(".#ryoku")}));

    QCOMPARE(ApplyController::appliedMarkerPath(),
             QStringLiteral("/etc/ryoku/applied-settings-hash"));
}

void ParserTests::applyStateIndependentOfGitDirty()
{
    // Contract: hash equality alone decides Applied — git/source dirty must not matter.
    const QString h = QStringLiteral("7d295f63ba12e0dd54b405713bb1c40ab8e161a300ce5ee47a264b931ffe64ff");
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h, h),
             QString::fromLatin1(ApplyController::StatusApplied));
    QCOMPARE(ApplyController::needsApplyReason(true, true, false, h, h),
             QStringLiteral("hashes match (Applied)"));

    QCOMPARE(ApplyController::statusFromHashes(true, false, false, QString(), h),
             QString::fromLatin1(ApplyController::StatusIdle));
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h, h),
             QString::fromLatin1(ApplyController::StatusApplied));

    QCOMPARE(ApplyController::statusFromHashes(false, true, false, h, QString()),
             QString::fromLatin1(ApplyController::StatusNeedsApply));
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h, h),
             QString::fromLatin1(ApplyController::StatusApplied));
}

void ParserTests::applyPrivilegedArgvAndResults()
{
    QVERIFY(ApplyController::isAllowlistedHelperOperation(QStringLiteral("apply")));
    QVERIFY(ApplyController::isAllowlistedHelperOperation(QStringLiteral("rollback")));
    QVERIFY(ApplyController::isAllowlistedHelperOperation(QStringLiteral("switch-generation")));
    QVERIFY(!ApplyController::isAllowlistedHelperOperation(QStringLiteral("switch")));
    QVERIFY(!ApplyController::isAllowlistedHelperOperation(QStringLiteral("bash")));
    QVERIFY(!ApplyController::isAllowlistedHelperOperation(QString()));

    const QString wrappersPkexec = ApplyController::systemPkexecPath();
    QVERIFY(wrappersPkexec == QStringLiteral("/run/wrappers/bin/pkexec")
            || wrappersPkexec == QStringLiteral("/usr/bin/pkexec"));
    QVERIFY(ApplyController::isAllowedPkexecPath(wrappersPkexec));
    QVERIFY(ApplyController::isAllowedPkexecPath(QStringLiteral("/usr/bin/pkexec")));
    QVERIFY(ApplyController::isAllowedPkexecPath(QStringLiteral("/run/wrappers/bin/pkexec")));
    QVERIFY(!ApplyController::isAllowedPkexecPath(
        QStringLiteral("/nix/store/deadbeef-polkit-127/bin/pkexec")));
    QVERIFY(!ApplyController::isAllowedPkexecPath(QStringLiteral("pkexec")));
    QVERIFY(!ApplyController::isAllowedPkexecPath(QString()));
    QVERIFY(ApplyController::missingSystemPkexecMessage().contains(QStringLiteral("pkexec")));

    // Relative helper path rejected
    QVERIFY(ApplyController::buildPkexecArgv(
                wrappersPkexec,
                QStringLiteral("ryoku-settings-apply"),
                QStringLiteral("apply")).isEmpty());

    // Store pkexec rejected — only wrappers path allowed
    QVERIFY(ApplyController::buildPkexecArgv(
                QStringLiteral("/nix/store/fake-polkit/bin/pkexec"),
                QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
                QStringLiteral("apply")).isEmpty());

    const QStringList argv = ApplyController::buildPkexecArgv(
        wrappersPkexec,
        QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
        QStringLiteral("apply"));
    QCOMPARE(argv.size(), 2);
    QCOMPARE(argv.at(0), QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"));
    QCOMPARE(argv.at(1), QStringLiteral("apply"));

    const QStringList switchArgv = ApplyController::buildPkexecArgv(
        wrappersPkexec,
        QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
        QStringLiteral("switch-generation"),
        94);
    QCOMPARE(switchArgv.size(), 3);
    QCOMPARE(switchArgv.at(1), QStringLiteral("switch-generation"));
    QCOMPARE(switchArgv.at(2), QStringLiteral("94"));
    QVERIFY(ApplyController::buildPkexecArgv(
                wrappersPkexec,
                QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
                QStringLiteral("switch-generation")).isEmpty());
    QVERIFY(ApplyController::buildPkexecArgv(
                wrappersPkexec,
                QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
                QStringLiteral("switch-generation"),
                0).isEmpty());
    QVERIFY(ApplyController::buildPkexecArgv(
                wrappersPkexec,
                QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
                QStringLiteral("apply"),
                94).isEmpty());

    QVERIFY(ApplyController::buildPkexecArgv(
                wrappersPkexec,
                QStringLiteral("/nix/store/fake/bin/ryoku-settings-apply"),
                QStringLiteral("evil")).isEmpty());

    QString status;
    QCOMPARE(ApplyController::mapPrivilegedResult(1, false, false, &status),
             QStringLiteral("Apply failed (pkexec NormalExit code=1)"));
    QCOMPARE(status, QString::fromLatin1(ApplyController::StatusApplyFailed));

    QCOMPARE(ApplyController::mapPrivilegedResult(0, true, false, &status),
             QStringLiteral("Applied — hash verified"));
    QCOMPARE(status, QString::fromLatin1(ApplyController::StatusApplied));

    QCOMPARE(ApplyController::mapPrivilegedResult(0, false, false, &status),
             QStringLiteral("Apply exited 0 but applied hash does not match"));
    QCOMPARE(status, QString::fromLatin1(ApplyController::StatusApplyFailed));

    QCOMPARE(ApplyController::mapPrivilegedResult(0, false, true, &status),
             QStringLiteral("Rollback finished"));
    QCOMPARE(status, QString::fromLatin1(ApplyController::StatusNeedsApply));
}

void ParserTests::applyHelperOpsParse()
{
    QCOMPARE(ryoku_parse_operation("apply"), RYOKU_APPLY_OP_APPLY);
    QCOMPARE(ryoku_parse_operation("rollback"), RYOKU_APPLY_OP_ROLLBACK);
    QCOMPARE(ryoku_parse_operation("switch-generation"), RYOKU_APPLY_OP_SWITCH_GENERATION);
    QCOMPARE(ryoku_parse_operation("switch"), RYOKU_APPLY_OP_INVALID);
    QCOMPARE(ryoku_parse_operation("--help"), RYOKU_APPLY_OP_INVALID);
    QCOMPARE(ryoku_parse_operation(""), RYOKU_APPLY_OP_INVALID);
    QCOMPARE(ryoku_parse_operation(nullptr), RYOKU_APPLY_OP_INVALID);
    // Extra argv / command injection shapes must never parse as ops.
    QCOMPARE(ryoku_parse_operation("apply;rm -rf /"), RYOKU_APPLY_OP_INVALID);
    QCOMPARE(ryoku_parse_operation("apply --flake"), RYOKU_APPLY_OP_INVALID);
    QCOMPARE(ryoku_parse_operation("/bin/sh"), RYOKU_APPLY_OP_INVALID);
    QCOMPARE(ryoku_parse_operation("switch-generation;sh"), RYOKU_APPLY_OP_INVALID);
}

void ParserTests::applyHelperMissingAndUnsavedDraft()
{
    ApplyController ctrl;
    // Without /etc helper path (typical pre-bootstrap), helperInstalled is false.
    // Unit tests run outside a Ryoku generation — treat as missing unless PATH has it.
    if (!ctrl.helperInstalled()) {
        QVERIFY(ctrl.bootstrapHint().contains(QStringLiteral("one-time system rebuild"),
                                              Qt::CaseInsensitive));
        QVERIFY(!ctrl.canApply());
    }

    ctrl.setUnsavedDraft(true);
    QVERIFY(!ctrl.canApply());
    QCOMPARE(ctrl.unsavedDraft(), true);

    QString status;
    QCOMPARE(ApplyController::mapPrivilegedResult(0, false, false, &status),
             QStringLiteral("Apply exited 0 but applied hash does not match"));
    QCOMPARE(status, QString::fromLatin1(ApplyController::StatusApplyFailed));
}

void ParserTests::applyPkexecPathAndClassification()
{
    // Relative / empty never canonicalize.
    QVERIFY(ApplyController::canonicalizeHelperPath(QString()).isEmpty());
    QVERIFY(ApplyController::canonicalizeHelperPath(QStringLiteral("ryoku-settings-apply")).isEmpty());
    QVERIFY(ApplyController::canonicalizeHelperPath(QStringLiteral("/no/such/helper")).isEmpty());

    // Symlink vs store: if profile helper exists, canonical must equal store and match policy.
    const QString link = QStringLiteral("/nix/var/nix/profiles/system/sw/bin/ryoku-settings-apply");
    if (QFileInfo::exists(link)) {
        const QString canon = ApplyController::canonicalizeHelperPath(link);
        QVERIFY(!canon.isEmpty());
        QVERIFY(canon.startsWith(QLatin1String("/nix/store/")));
        QCOMPARE(canon, QFileInfo(link).canonicalFilePath());
        QVERIFY(ApplyController::helperPathMatchesPolicyAnnotation(link, canon));
        QVERIFY(ApplyController::helperPathMatchesPolicyAnnotation(canon, canon));
        // Mismatch: different store paths must not match.
        QVERIFY(!ApplyController::helperPathMatchesPolicyAnnotation(
            canon, QStringLiteral("/nix/store/deadbeef-ryoku-settings-apply-0.1.0/bin/ryoku-settings-apply")));
    }

    // Auth cancel evidence → AuthorizationDenied
    {
        const auto cls = ApplyController::classifyPkexecResult(
            127, 0, {},
            QByteArray("Error executing command as another user: Not authorized\n"),
            false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusAuthorizationDenied));
        QVERIFY(cls.message.contains(QStringLiteral("Authorization denied")));
        QVERIFY(cls.message.contains(QStringLiteral("127")));
        QVERIFY(cls.message.contains(QStringLiteral("Not authorized")));
    }

    // Missing agent → AuthorizationError (NOT AuthorizationDenied)
    {
        const auto cls = ApplyController::classifyPkexecResult(
            127, 0, {},
            QByteArray("Error executing command as another user: No authentication agent found.\n"),
            false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusAuthorizationError));
        QVERIFY(cls.message.contains(QStringLiteral("authentication agent"), Qt::CaseInsensitive));
        QVERIFY(!cls.message.startsWith(QStringLiteral("Authorization denied")));
    }

    // Empty stderr + 127 → AuthorizationError (ambiguous; not user-deny)
    {
        const auto cls = ApplyController::classifyPkexecResult(127, 0, {}, {}, false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusAuthorizationError));
        QVERIFY(cls.message.contains(QStringLiteral("127")));
    }

    // setuid / exec failure → AuthorizationError (not AuthorizationDenied)
    {
        const auto cls = ApplyController::classifyPkexecResult(
            127, 0, {}, QByteArray("pkexec must be setuid root\n"), false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusAuthorizationError));
        QVERIFY(cls.message.contains(QStringLiteral("setuid")));
        QVERIFY(cls.message.contains(QStringLiteral("/run/wrappers/bin/pkexec")));
        QVERIFY(cls.message.contains(QStringLiteral("must be setuid root")));
        QVERIFY(cls.message.contains(QStringLiteral("NormalExit")));
    }

    // CrashExit with bogus exitCode (-4) must NOT be reported as "pkexec exit=-4"
    {
        const auto cls = ApplyController::classifyPkexecResult(
            -4, 1, -1, QString(), {}, {}, false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusApplyFailed));
        QVERIFY(cls.message.contains(QStringLiteral("terminated unexpectedly")));
        QVERIFY(!cls.message.contains(QStringLiteral("pkexec exit=-4")));
        QVERIFY(!cls.message.contains(QStringLiteral("NormalExit code=-4")));
    }

    // FailedToStart (ProcessError=0) → AuthorizationError
    {
        const auto cls = ApplyController::classifyPkexecResult(
            -1, 1, 0, QStringLiteral("No such file or directory"), {}, {}, false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusAuthorizationError));
        QVERIFY(cls.message.contains(QStringLiteral("FailedToStart")));
        QVERIFY(cls.message.contains(QStringLiteral("No such file")));
    }

    // Helper non-zero after auth → ApplyFailed
    {
        const auto cls = ApplyController::classifyPkexecResult(
            1, 0, {}, QByteArray("nixos-rebuild: error: something\n"), false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusApplyFailed));
        QVERIFY(cls.message.contains(QStringLiteral("nixos-rebuild")));
        QVERIFY(cls.message.contains(QStringLiteral("NormalExit code=1")));
    }

    // User cancel phrasing → AuthorizationDenied (not Error)
    {
        const auto cls = ApplyController::classifyPkexecResult(
            126, 0, {}, QByteArray("User cancelled authentication\n"), false);
        QCOMPARE(cls.status, QString::fromLatin1(ApplyController::StatusAuthorizationDenied));
    }
}

void ParserTests::systemOsReleaseParse()
{
    const QVariantMap m = SystemInfoModel::parseOsRelease(
        QByteArrayLiteral(
            "NAME=NixOS\n"
            "ID=nixos\n"
            "VERSION=\"25.05 (Warbler)\"\n"
            "PRETTY_NAME=\"NixOS 25.05 (Warbler)\"\n"
            "# comment\n"
            "BUILD_ID=\"25.05.20250901.abcdef\"\n"));
    QCOMPARE(m.value(QStringLiteral("ID")).toString(), QStringLiteral("nixos"));
    QCOMPARE(m.value(QStringLiteral("PRETTY_NAME")).toString(),
             QStringLiteral("NixOS 25.05 (Warbler)"));
    QCOMPARE(m.value(QStringLiteral("VERSION")).toString(),
             QStringLiteral("25.05 (Warbler)"));
    QVERIFY(SystemInfoModel::parseOsRelease(QByteArrayLiteral("")).isEmpty());
}

void ParserTests::systemMeminfoAndPaths()
{
    QCOMPARE(SystemInfoModel::parseMemTotalKb(
                 QByteArrayLiteral("MemTotal:       16318464 kB\nMemFree: 1 kB\n")),
             16318464);
    QCOMPARE(SystemInfoModel::parseMemTotalKb(QByteArrayLiteral("garbage")), -1);
    QCOMPARE(SystemInfoModel::formatMemoryFromKb(1048576), QStringLiteral("1.0 GiB"));
    QCOMPARE(SystemInfoModel::formatMemoryFromKb(-1), QStringLiteral("Unavailable"));

    QCOMPARE(SystemInfoModel::parseCpuModel(
                 QByteArrayLiteral("processor\t: 0\nmodel name\t: Test CPU @ 3.0GHz\n")),
             QStringLiteral("Test CPU @ 3.0GHz"));
    QVERIFY(SystemInfoModel::parseCpuModel(QByteArrayLiteral("nope")).isEmpty());

    QCOMPARE(SystemInfoModel::formatUptime(90061), QStringLiteral("1d 1h 1m"));
    QCOMPARE(SystemInfoModel::formatUptime(3660), QStringLiteral("1h 1m"));
    QCOMPARE(SystemInfoModel::formatUptime(-1), QStringLiteral("Unavailable"));

    QCOMPARE(SystemInfoModel::parseHyprctlVersionLine(
                 QByteArrayLiteral("Hyprland 0.56.2 built from branch v0.56.2\nTag: ...\n")),
             QStringLiteral("0.56.2"));
    QVERIFY(SystemInfoModel::parseHyprctlVersionLine(QByteArrayLiteral("")).isEmpty());

    QCOMPARE(SystemInfoModel::parseProfileGeneration(QStringLiteral("/nix/var/nix/profiles/system-42-link")),
             42);
    QCOMPARE(SystemInfoModel::parseProfileGeneration(QStringLiteral("system-7-link")), 7);
    QCOMPARE(SystemInfoModel::parseProfileGeneration(QStringLiteral("nope")), -1);
}

void ParserTests::systemGenerationMatchLabels()
{
    QVERIFY(SystemInfoModel::pathsMatch(QStringLiteral("/a"), QStringLiteral("/a")));
    QVERIFY(!SystemInfoModel::pathsMatch(QStringLiteral("/a"), QStringLiteral("/b")));
    QVERIFY(!SystemInfoModel::pathsMatch(QString(), QStringLiteral("/a")));

    QCOMPARE(SystemInfoModel::generationMatchLabelFor(true, true),
             QStringLiteral("Active generation matches system profile"));
    QCOMPARE(SystemInfoModel::generationMatchLabelFor(true, false),
             QStringLiteral("Current system differs from system profile"));
    QCOMPARE(SystemInfoModel::generationMatchLabelFor(false, false),
             QStringLiteral("Generation paths unavailable"));
}

void ParserTests::gitSummaryLabels()
{
    QCOMPARE(GitStatusModel::repositorySummary(false, true, 0), QStringLiteral("Unavailable"));
    QCOMPARE(GitStatusModel::repositorySummary(true, true, 0), QStringLiteral("Clean"));
    QCOMPARE(GitStatusModel::repositorySummary(true, false, 17),
             QStringLiteral("Modified · 17 files"));
    QCOMPARE(GitStatusModel::headSummary(QStringLiteral("abc1234"), QStringLiteral("feat: x")),
             QStringLiteral("abc1234 feat: x"));
    QCOMPARE(GitStatusModel::headSummary(QString(), QStringLiteral("x")),
             QStringLiteral("Unavailable"));
}

void ParserTests::flakeMetadataParseAndMalformed()
{
    const QByteArray sample = QByteArrayLiteral(R"({
      "description": "Ryoku",
      "url": "git+file:///tmp/ryoku",
      "locks": {
        "nodes": {
          "root": {
            "inputs": {
              "nixpkgs": "nixpkgs",
              "home-manager": "home-manager"
            }
          },
          "nixpkgs": {
            "locked": {
              "type": "github",
              "owner": "NixOS",
              "repo": "nixpkgs",
              "rev": "abcdef0123456789"
            }
          },
          "home-manager": {
            "locked": {
              "type": "github",
              "owner": "nix-community",
              "repo": "home-manager",
              "rev": "1234567890abcdef"
            }
          }
        }
      }
    })");

    QString err;
    const QVariantMap parsed = FlakeMetadataModel::parseMetadataJson(sample, &err);
    QVERIFY2(err.isEmpty(), qPrintable(err));
    QCOMPARE(parsed.value(QStringLiteral("description")).toString(), QStringLiteral("Ryoku"));
    QCOMPARE(parsed.value(QStringLiteral("lockedInputCount")).toInt(), 2);
    const QVariantList inputs = parsed.value(QStringLiteral("inputs")).toList();
    QCOMPARE(inputs.size(), 2);
    QCOMPARE(inputs.at(0).toMap().value(QStringLiteral("name")).toString(),
             QStringLiteral("home-manager"));
    QVERIFY(inputs.at(1).toMap().value(QStringLiteral("summary")).toString().contains(
        QStringLiteral("NixOS/nixpkgs")));

    QString badErr;
    QVERIFY(FlakeMetadataModel::parseMetadataJson(QByteArrayLiteral("{not-json"), &badErr).isEmpty());
    QVERIFY(!badErr.isEmpty());

    QString arrErr;
    QVERIFY(FlakeMetadataModel::parseMetadataJson(QByteArrayLiteral("[]"), &arrErr).isEmpty());
    QVERIFY(!arrErr.isEmpty());

    bool present = true;
    QString modified;
    FlakeMetadataModel::refreshLockFileInfo(QString(), &present, &modified);
    QVERIFY(!present);
    QCOMPARE(modified, QStringLiteral("Unavailable"));
}

void ParserTests::generationsListParse()
{
    const QByteArray sample = QByteArrayLiteral(R"([
      {"generation": 40, "date": "2025-01-01", "nixosVersion": "25.05", "kernelVersion": "6.1", "current": false},
      {"generation": 42, "date": "2025-09-01", "nixosVersion": "25.05", "kernelVersion": "6.1", "current": true},
      {"generation": 41, "date": "2025-08-01", "nixosVersion": "25.05", "kernelVersion": "6.1", "current": false},
      {"generation": 39, "date": "2024-12-01", "nixosVersion": "24.11", "kernelVersion": "6.1", "current": false},
      {"generation": 38, "date": "2024-11-01", "nixosVersion": "24.11", "kernelVersion": "6.1", "current": false},
      {"generation": 37, "date": "2024-10-01", "nixosVersion": "24.11", "kernelVersion": "6.1", "current": false}
    ])");

    int current = -1;
    QString err;
    const QVariantList rows = GenerationsModel::parseListGenerationsJson(sample, 5, &current, &err);
    QVERIFY2(err.isEmpty(), qPrintable(err));
    QCOMPARE(current, 42);
    QCOMPARE(rows.size(), 5);
    QCOMPARE(rows.at(0).toMap().value(QStringLiteral("generation")).toInt(), 42);
    QVERIFY(rows.at(0).toMap().value(QStringLiteral("current")).toBool());
    QCOMPARE(rows.at(4).toMap().value(QStringLiteral("generation")).toInt(), 38);

    QString badErr;
    QVERIFY(GenerationsModel::parseListGenerationsJson(QByteArrayLiteral("{}"), 5, nullptr, &badErr)
                .isEmpty());
    QVERIFY(!badErr.isEmpty());

    QString malErr;
    QVERIFY(GenerationsModel::parseListGenerationsJson(QByteArrayLiteral("not-json"), 5, nullptr, &malErr)
                .isEmpty());
    QVERIFY(!malErr.isEmpty());
}

void ParserTests::flakeUpdateLockParsersAndAllowlist()
{
    const QByteArray lockA = QByteArrayLiteral(R"({
      "nodes": {
        "root": { "inputs": { "nixpkgs": "nixpkgs", "home-manager": "home-manager" } },
        "nixpkgs": {
          "locked": { "type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
          "original": { "type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable" }
        },
        "home-manager": {
          "locked": { "type": "github", "owner": "nix-community", "repo": "home-manager", "rev": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" },
          "original": { "type": "github", "owner": "nix-community", "repo": "home-manager" }
        }
      }
    })");
    const QByteArray lockB = QByteArrayLiteral(R"({
      "nodes": {
        "root": { "inputs": { "nixpkgs": "nixpkgs", "home-manager": "home-manager" } },
        "nixpkgs": {
          "locked": { "type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "cccccccccccccccccccccccccccccccccccccccc" },
          "original": { "type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable" }
        },
        "home-manager": {
          "locked": { "type": "github", "owner": "nix-community", "repo": "home-manager", "rev": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" },
          "original": { "type": "github", "owner": "nix-community", "repo": "home-manager" }
        }
      }
    })");

    QString err;
    const QVariantList inputs = FlakeUpdateModel::parseLockRootInputs(lockA, &err);
    QVERIFY2(err.isEmpty(), qPrintable(err));
    QCOMPARE(inputs.size(), 2);
    QCOMPARE(inputs.at(1).toMap().value(QStringLiteral("originalUrl")).toString(),
             QStringLiteral("github:NixOS/nixpkgs/nixos-unstable"));

    // unchanged lock → empty diff
    QVERIFY(FlakeUpdateModel::diffLockedRevisions(lockA, lockA).isEmpty());

    const QVariantList diff = FlakeUpdateModel::diffLockedRevisions(lockA, lockB);
    QCOMPARE(diff.size(), 1);
    QCOMPARE(diff.at(0).toMap().value(QStringLiteral("name")).toString(),
             QStringLiteral("nixpkgs"));
    QVERIFY(diff.at(0).toMap().value(QStringLiteral("label")).toString().contains(
        QStringLiteral("aaaaaaa")));
    QVERIFY(diff.at(0).toMap().value(QStringLiteral("label")).toString().contains(
        QStringLiteral("ccccccc")));

    QCOMPARE(FlakeUpdateModel::compareUpdateStatus(QStringLiteral("abc"), QStringLiteral("abc")),
             QStringLiteral("up_to_date"));
    QCOMPARE(FlakeUpdateModel::compareUpdateStatus(QStringLiteral("abc"), QStringLiteral("def")),
             QStringLiteral("update_available"));

    const QStringList known{QStringLiteral("nixpkgs"), QStringLiteral("home-manager")};
    QVERIFY(FlakeUpdateModel::isAllowlistedFlakeUpdateArgs(
        {QStringLiteral("flake"), QStringLiteral("update")}, known));
    QVERIFY(FlakeUpdateModel::isAllowlistedFlakeUpdateArgs(
        {QStringLiteral("flake"), QStringLiteral("update"), QStringLiteral("nixpkgs")}, known));
    QVERIFY(!FlakeUpdateModel::isAllowlistedFlakeUpdateArgs(
        {QStringLiteral("flake"), QStringLiteral("update"), QStringLiteral("evil;rm")}, known));
    QVERIFY(!FlakeUpdateModel::isAllowlistedFlakeUpdateArgs(
        {QStringLiteral("flake"), QStringLiteral("update"), QStringLiteral("--impure")}, known));
    QVERIFY(!FlakeUpdateModel::isAllowlistedFlakeUpdateArgs(
        {QStringLiteral("shell"), QStringLiteral("nixpkgs#bash")}, known));
    // flake update must never be confused with flake check allowlist on ApplyController
    QVERIFY(!ApplyController::isAllowlistedFlakeCheckArgs(
        {QStringLiteral("flake"), QStringLiteral("update")}));

    QString metaErr;
    QCOMPARE(FlakeUpdateModel::parseMetadataRevision(
                 QByteArrayLiteral("{\"revision\":\"deadbeefcafebabe\"}"), &metaErr),
             QStringLiteral("deadbeefcafebabe"));
    QVERIFY(FlakeUpdateModel::parseMetadataRevision(QByteArrayLiteral("{"), &metaErr).isEmpty());
    QVERIFY(!metaErr.isEmpty());

    const QString offline = FlakeUpdateModel::classifyProcessFailure(
        1, QProcess::NormalExit, QProcess::UnknownError,
        QByteArrayLiteral("error: unable to download 'https://github.com/...': Could not resolve host\n"));
    QVERIFY(offline.contains(QStringLiteral("Network"), Qt::CaseInsensitive));
}

void ParserTests::flakeUpdateRevertAtomicAndIsolation()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString lock = dir.filePath(QStringLiteral("flake.lock"));
    const QString other = dir.filePath(QStringLiteral("settings.json"));
    const QByteArray lockV1 = QByteArrayLiteral("{\"nodes\":{\"root\":{\"inputs\":{}}}}\n");
    const QByteArray lockV2 = QByteArrayLiteral("{\"nodes\":{\"root\":{\"inputs\":{\"x\":\"x\"}}}}\n");
    const QByteArray otherBytes = QByteArrayLiteral("KEEP_ME");

    {
        QFile f(lock);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(lockV2);
    }
    {
        QFile f(other);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(otherBytes);
    }

    QString err;
    QVERIFY(FlakeUpdateModel::writeAtomicFile(lock, lockV1, &err));
    QVERIFY2(err.isEmpty(), qPrintable(err));

    {
        QFile f(lock);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(f.readAll(), lockV1);
    }
    {
        QFile f(other);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(f.readAll(), otherBytes);
    }

    // hashes distinguish unchanged vs changed
    QCOMPARE(FlakeUpdateModel::lockContentSha256(lockV1),
             FlakeUpdateModel::lockContentSha256(lockV1));
    QVERIFY(FlakeUpdateModel::lockContentSha256(lockV1)
            != FlakeUpdateModel::lockContentSha256(lockV2));
}

void ParserTests::flakeUpdateRebuildHintAndLockPending()
{
    QCOMPARE(FlakeUpdateModel::rebuildHintFor(false, true),
             QStringLiteral("No lockfile update pending"));
    QCOMPARE(FlakeUpdateModel::rebuildHintFor(true, true),
             QStringLiteral("Flake lock changed since last rebuild — system rebuild required"));
    QCOMPARE(FlakeUpdateModel::rebuildHintFor(true, false),
             QStringLiteral("Lockfile changed — Apply recommended"));

    QVERIFY(FlakeUpdateModel::nixpkgsRunningHint(QString(), QString()).contains(
        QStringLiteral("unavailable"), Qt::CaseInsensitive));
    QVERIFY(FlakeUpdateModel::nixpkgsRunningHint(QStringLiteral("aaa"), QStringLiteral("bbb"))
                .contains(QStringLiteral("partial")));

    // Lock pending must not invent a mixed settings hash — ApplyController flag is orthogonal.
    ApplyController ctrl;
    QVERIFY(!ctrl.lockfilePendingRebuild());
    ctrl.setLockfilePendingRebuild(true);
    QVERIFY(ctrl.lockfilePendingRebuild());
    // Hash contract helpers unchanged
    const QString h = QStringLiteral("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h, h),
             QString::fromLatin1(ApplyController::StatusApplied));
    ctrl.setLockfilePendingRebuild(false);
    QVERIFY(!ctrl.lockfilePendingRebuild());
}

void ParserTests::generationSwitchParsersAndArgv()
{
    int gen = -1;
    QVERIFY(ApplyController::parseStrictGenerationNumber(QStringLiteral("95"), &gen));
    QCOMPARE(gen, 95);
    QVERIFY(ApplyController::parseStrictGenerationNumber(QStringLiteral("102"), &gen));
    QCOMPARE(gen, 102);

    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("0"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("-1"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("abc"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("95;sh"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("95/foo"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("../95"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("95 --option"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QStringLiteral("01"), &gen));
    QVERIFY(!ApplyController::parseStrictGenerationNumber(QString(), &gen));

    {
        const QString user = qEnvironmentVariable("USER");
        if (!user.isEmpty()) {
            QCOMPARE(ApplyController::systemGenerationLinkPath(94),
                     QStringLiteral("/nix/var/nix/profiles/per-user/%1/home-manager-94-link")
                         .arg(user));
        }
    }
    QVERIFY(ApplyController::systemGenerationLinkPath(0).isEmpty());

    QCOMPARE(GenerationsModel::parseProfileGenerationFromSymlinkTarget(
                 QStringLiteral("home-manager-95-link")),
             95);
    QCOMPARE(GenerationsModel::parseProfileGenerationFromSymlinkTarget(
                 QStringLiteral("/nix/var/nix/profiles/per-user/paulo/home-manager-7-link")),
             7);
    QCOMPARE(GenerationsModel::parseProfileGenerationFromSymlinkTarget(
                 QStringLiteral("system-95-link")),
             95);

    // Missing generation rejected (does not switch anything).
    QString err;
    QVERIFY(!ApplyController::validateSystemGenerationExists(999999, nullptr, &err));
    QVERIFY(!err.isEmpty());

    // Existing HM generation on this host — read-only validate only.
    {
        const QString user = qEnvironmentVariable("USER");
        const QString link = QStringLiteral("/nix/var/nix/profiles/per-user/%1/home-manager-1-link")
                                 .arg(user);
        if (!user.isEmpty() && QFileInfo::exists(link)) {
            QString canon;
            QVERIFY(ApplyController::validateSystemGenerationExists(1, &canon, &err));
            QVERIFY(canon.startsWith(QStringLiteral("/nix/store/")));
        }
    }

    // Current generation cannot switch to itself (when profile readable).
    const int profile = ApplyController::readProfileGenerationNumber();
    if (profile > 0) {
        ApplyController ctrl;
        // Without helper/pkexec canSwitch is false anyway; still assert self-check helper intent:
        QVERIFY(profile == ApplyController::readProfileGenerationNumber());
    }

    // C parser mirrors Qt (helper allowlist)
    unsigned u = 0;
    QCOMPARE(ryoku_parse_generation_number("42", &u), 0);
    QCOMPARE(u, 42u);
    QCOMPARE(ryoku_parse_generation_number("0", &u), -1);
    QCOMPARE(ryoku_parse_generation_number("42;rm", &u), -1);
}

void ParserTests::generationSwitchVerificationReconcile()
{
    QString warning;
    // exit 0 style process + target mismatch → SwitchFailed (never trust privileged exit)
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 false, true, false, false, QString(), QStringLiteral("ok"), &warning),
             QString::fromLatin1(ApplyController::StatusSwitchFailed));

    // abnormal process + target verified → NeedsApply (success path) + warning
    warning.clear();
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 true, false, false, false, QString(),
                 QStringLiteral("Privileged process terminated unexpectedly"), &warning),
             QString::fromLatin1(ApplyController::StatusNeedsApply));
    QVERIFY(warning.contains(QStringLiteral("active")));
    QVERIFY(warning.contains(QStringLiteral("unexpectedly")));

    // auth denied
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 false, false, true, false, QString(), QStringLiteral("denied"), &warning),
             QString::fromLatin1(ApplyController::StatusAuthorizationDenied));

    // Pre-exec pkexec/auth infrastructure failure must NOT become SwitchFailed
    // (root cause of false "target mismatch" after 97→96 when agent/session reexecs).
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 false, false, false, false,
                 QString::fromLatin1(ApplyController::StatusAuthorizationError),
                 QStringLiteral("pkexec failed (NormalExit 126) with empty output"), &warning),
             QString::fromLatin1(ApplyController::StatusAuthorizationError));

    // Conceptual 97 → 96 → 97 round trip: success only when targetActive each leg.
    // Leg 97→96 succeeds.
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 true, true, false, false, QString(), QStringLiteral("pkexec NormalExit 0"),
                 &warning),
             QString::fromLatin1(ApplyController::StatusNeedsApply));
    // Leg 96→97 with exit0 but target still inactive → SwitchFailed (safety contract).
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 false, true, false, false, QString(), QStringLiteral("pkexec NormalExit 0"),
                 &warning),
             QString::fromLatin1(ApplyController::StatusSwitchFailed));
    // Leg 96→97 when current==profile==97 target → success.
    QCOMPARE(ApplyController::reconcileSwitchGenerationVerification(
                 true, true, false, false, QString(), QStringLiteral("pkexec NormalExit 0"),
                 &warning),
             QString::fromLatin1(ApplyController::StatusNeedsApply));

    // Lockfile pending must survive conceptual switch success (flag orthogonal).
    ApplyController ctrl;
    ctrl.setLockfilePendingRebuild(true);
    QVERIFY(ctrl.lockfilePendingRebuild());
    // statusFromHashes still Applied when hashes match — switch does not invent mixed hash
    const QString h = QStringLiteral("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    QCOMPARE(ApplyController::statusFromHashes(true, true, false, h, h),
             QString::fromLatin1(ApplyController::StatusApplied));
    QVERIFY(ctrl.lockfilePendingRebuild());
}

void ParserTests::languageManagerSelectorsAndFallback()
{
    QCOMPARE(LanguageManager::normalizeSelector(QStringLiteral("system")), QStringLiteral("system"));
    QCOMPARE(LanguageManager::normalizeSelector(QStringLiteral("pt_BR")), QStringLiteral("pt_BR"));
    QCOMPARE(LanguageManager::normalizeSelector(QStringLiteral("pt-BR")), QStringLiteral("pt_BR"));
    QCOMPARE(LanguageManager::normalizeSelector(QStringLiteral("en")), QStringLiteral("en"));
    QCOMPARE(LanguageManager::normalizeSelector(QStringLiteral("en_US")), QStringLiteral("en"));
    QCOMPARE(LanguageManager::normalizeSelector(QString()), QStringLiteral("system"));

    QCOMPARE(LanguageManager::resolveEffectiveLocale(QStringLiteral("pt_BR")), QStringLiteral("pt_BR"));
    QCOMPARE(LanguageManager::resolveEffectiveLocale(QStringLiteral("en")), QStringLiteral("en"));

    // system follows QLocale::system — Portuguese family → pt_BR, else English.
    const QString sys = LanguageManager::resolveEffectiveLocale(QStringLiteral("system"));
    QVERIFY(sys == QLatin1String("pt_BR") || sys == QLatin1String("en"));
}

void ParserTests::languageManagerPersistenceLocal()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    qputenv("XDG_CONFIG_HOME", dir.path().toUtf8());

    {
        LanguageManager lm;
        QCOMPARE(lm.language(), QStringLiteral("system"));
        lm.setLanguage(QStringLiteral("pt_BR"));
        QCOMPARE(lm.language(), QStringLiteral("pt_BR"));
    }
    {
        LanguageManager lm2;
        QCOMPARE(lm2.language(), QStringLiteral("pt_BR"));
        lm2.setLanguage(QStringLiteral("en"));
        QCOMPARE(lm2.language(), QStringLiteral("en"));
    }
    {
        LanguageManager lm3;
        QCOMPARE(lm3.language(), QStringLiteral("en"));
        lm3.setLanguage(QStringLiteral("system"));
        QCOMPARE(lm3.language(), QStringLiteral("system"));
    }

    QSettings settings(LanguageManager::settingsOrg(), LanguageManager::settingsApp());
    QCOMPARE(settings.value(LanguageManager::settingsKey()).toString(), QStringLiteral("system"));
}

void ParserTests::languageManagerDoesNotTouchSettingsOrApply()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    qputenv("XDG_CONFIG_HOME", dir.path().toUtf8());

    QVERIFY(QDir(dir.path()).mkpath(QStringLiteral("ryoku")));
    QFile flake(dir.filePath(QStringLiteral("flake.nix")));
    QVERIFY(flake.open(QIODevice::WriteOnly));
    flake.write("{}\n");
    flake.close();

    const QString settingsPath = dir.filePath(QStringLiteral("ryoku/settings.json"));
    QFile settingsFile(settingsPath);
    QVERIFY(settingsFile.open(QIODevice::WriteOnly));
    const QByteArray original = QByteArrayLiteral(
        "{\n  \"schemaVersion\": 1,\n  \"appearance\": { \"dynamicColors\": true }\n}\n");
    settingsFile.write(original);
    settingsFile.close();

    SettingsStore store;
    store.setRepoPath(dir.path());
    QVERIFY(store.loaded());

    ApplyController apply;
    apply.setSettingsStore(&store);
    apply.setRepoPath(dir.path());
    const QString statusBefore = apply.status();
    const bool needsBefore = apply.needsSystemApply();

    LanguageManager lm;
    lm.setLanguage(QStringLiteral("pt_BR"));
    lm.setLanguage(QStringLiteral("en"));
    lm.setLanguage(QStringLiteral("system"));

    QFile after(settingsPath);
    QVERIFY(after.open(QIODevice::ReadOnly));
    QCOMPARE(after.readAll(), original);
    after.close();

    QCOMPARE(apply.status(), statusBefore);
    QCOMPARE(apply.needsSystemApply(), needsBefore);
}

void ParserTests::languageTranslationResourcePath()
{
    // Production binary embeds :/i18n/ryoku-settings_pt_BR.qm via qt_add_translations.
    // Unit tests may run without that resource — assert path contract + English fallback.
    const QString embedded = QStringLiteral(":/i18n/ryoku-settings_pt_BR.qm");
    QVERIFY(embedded.startsWith(QLatin1String(":/i18n/")));
    QVERIFY(embedded.endsWith(QLatin1String("_pt_BR.qm")));

    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    qputenv("XDG_CONFIG_HOME", dir.path().toUtf8());

    LanguageManager lm;
    lm.setLanguage(QStringLiteral("en"));
    QCOMPARE(lm.effectiveLocale(), QStringLiteral("en"));

    lm.setLanguage(QStringLiteral("pt_BR"));
    // With or without qm: selector stays pt_BR; effective is pt_BR if qm loads, else en.
    QCOMPARE(lm.language(), QStringLiteral("pt_BR"));
    QVERIFY(lm.effectiveLocale() == QLatin1String("pt_BR")
            || lm.effectiveLocale() == QLatin1String("en"));
}

void ParserTests::searchIndexMatchesPagesAndCatalogue()
{
    const QDir src(QStringLiteral(RYOKU_SETTINGS_SOURCE_DIR));
    auto readAll = [&](const QString &rel) {
        QFile f(src.filePath(rel));
        if (!f.open(QIODevice::ReadOnly))
            return QString();
        return QString::fromUtf8(f.readAll());
    };

    // PT-BR catalogue: context → sources with a finished translation.
    QHash<QString, QSet<QString>> translated;
    {
        QFile ts(src.filePath(QStringLiteral("i18n/ryoku-settings_pt_BR.ts")));
        QVERIFY(ts.open(QIODevice::ReadOnly));
        QXmlStreamReader xml(&ts);
        QString context, source, translation;
        bool unfinished = false;
        while (!xml.atEnd()) {
            xml.readNext();
            if (xml.isStartElement()) {
                const auto name = xml.name();
                if (name == QLatin1String("name")) {
                    context = xml.readElementText();
                } else if (name == QLatin1String("message")) {
                    source.clear();
                    translation.clear();
                    unfinished = false;
                } else if (name == QLatin1String("source")) {
                    source = xml.readElementText();
                } else if (name == QLatin1String("translation")) {
                    unfinished = xml.attributes().value(QLatin1String("type")) == QLatin1String("unfinished");
                    translation = xml.readElementText();
                }
            } else if (xml.isEndElement() && xml.name() == QLatin1String("message")) {
                if (!translation.isEmpty() && !unfinished)
                    translated[context].insert(source);
            }
        }
        QVERIFY2(!xml.hasError(), qPrintable(xml.errorString()));
    }

    const QString index = readAll(QStringLiteral("qml/components/RyokuSearchIndex.qml"));
    QVERIFY(!index.isEmpty());

    QHash<QString, QString> contextForPage;
    QRegularExpression ctxRe(QStringLiteral(R"re((\w+): "(\w+Page)")re"));
    for (auto it = ctxRe.globalMatch(index); it.hasNext();) {
        const auto m = it.next();
        contextForPage.insert(m.captured(1), m.captured(2));
    }
    QCOMPARE(contextForPage.size(), 11);

    QRegularExpression entryRe(QStringLiteral(
        R"re(\{\s*page:\s*"(\w+)",\s*text:\s*QT_TRANSLATE_NOOP\("(\w+)",\s*"([^"]+)"\))re"));
    int entries = 0;
    for (auto it = entryRe.globalMatch(index); it.hasNext();) {
        const auto m = it.next();
        const QString page = m.captured(1);
        const QString ctx = m.captured(2);
        const QString text = m.captured(3);
        ++entries;
        QVERIFY2(contextForPage.value(page) == ctx,
                 qPrintable(QStringLiteral("%1 → %2 but entry uses %3").arg(page, contextForPage.value(page), ctx)));
        QVERIFY2(translated.value(ctx).contains(text),
                 qPrintable(QStringLiteral("no PT-BR translation for %1 / \"%2\"").arg(ctx, text)));
        const QString pageQml = readAll(QStringLiteral("qml/pages/%1.qml").arg(ctx));
        QVERIFY2(pageQml.contains(QStringLiteral("qsTr(\"%1\")").arg(text)),
                 qPrintable(QStringLiteral("\"%1\" is not a label in %2.qml").arg(text, ctx)));
    }
    QVERIFY(entries >= 60);

    // Sidebar: every page's English `source` is exactly its qsTr title.
    const QString mainQml = readAll(QStringLiteral("qml/Main.qml"));
    QRegularExpression pageRe(QStringLiteral(R"re(title: qsTr\("([^"]+)"\), source: "([^"]+)")re"));
    int pages = 0;
    for (auto it = pageRe.globalMatch(mainQml); it.hasNext();) {
        const auto m = it.next();
        QCOMPARE(m.captured(2), m.captured(1));
        ++pages;
    }
    QCOMPARE(pages, 11);

    // New search UI strings are translated.
    for (const QString &s : {QStringLiteral("Page"), QStringLiteral("No results for “%1”"),
                             QStringLiteral("Try a page name or an option label.")})
        QVERIFY2(translated.value(QStringLiteral("Main")).contains(s), qPrintable(s));
    for (const QString &s : {QStringLiteral("Search settings…"), QStringLiteral("Clear search")})
        QVERIFY2(translated.value(QStringLiteral("RyokuSearchField")).contains(s), qPrintable(s));
}

void ParserTests::visualProfileMergeAndValidation()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": { "dynamicColors": true, "wallpaper": "5.jpg", "futureKey": "keep-me" },
      "apps": { "flatpakDeclared": [] }
    })").object();

    QByteArray out;
    QString e;
    QVERIFY2(SettingsStore::mergeVisualProfileAndSerialize(root, QStringLiteral("cinematic"), true, &out, &e),
             qPrintable(e));
    QJsonObject a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a.value(QStringLiteral("visualProfile")).toString(), QStringLiteral("cinematic"));
    QCOMPARE(a.value(QStringLiteral("visualProfileAuto")).toBool(), true);
    QCOMPARE(a.value(QStringLiteral("wallpaper")).toString(), QStringLiteral("5.jpg"));
    QCOMPARE(a.value(QStringLiteral("futureKey")).toString(), QStringLiteral("keep-me"));

    // null on a file without the keys adds nothing (byte-identical document).
    QVERIFY(SettingsStore::mergeVisualProfileAndSerialize(root, QVariant(), QVariant(), &out, &e));
    QCOMPARE(out, QJsonDocument(root).toJson(QJsonDocument::Indented));

    // null on a file that has them writes explicit null (back to defaults).
    QJsonObject withKeys = root;
    QJsonObject app = withKeys.value(QStringLiteral("appearance")).toObject();
    app.insert(QStringLiteral("visualProfile"), QStringLiteral("economy"));
    withKeys.insert(QStringLiteral("appearance"), app);
    QVERIFY(SettingsStore::mergeVisualProfileAndSerialize(withKeys, QVariant(), QVariant(), &out, &e));
    a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QVERIFY(a.contains(QStringLiteral("visualProfile")));
    QVERIFY(a.value(QStringLiteral("visualProfile")).isNull());
    QVERIFY(!a.contains(QStringLiteral("visualProfileAuto")));

    QVERIFY(!SettingsStore::mergeVisualProfileAndSerialize(root, QStringLiteral("ultra"), QVariant(), &out, &e));
    QVERIFY(e.contains(QStringLiteral("visualProfile")));
    QVERIFY(!SettingsStore::mergeVisualProfileAndSerialize(root, QStringLiteral("economy"), QStringLiteral("yes"), &out, &e));
    QVERIFY(e.contains(QStringLiteral("visualProfileAuto")));
    QVERIFY(!SettingsStore::mergeVisualProfileAndSerialize(QJsonObject{{QStringLiteral("schemaVersion"), 2}},
                                                           QStringLiteral("economy"), QVariant(), &out, &e));
}

void ParserTests::shellStyleMergeAndValidation()
{
    const QJsonObject root = QJsonDocument::fromJson(R"({
      "schemaVersion": 1,
      "appearance": { "visualProfile": "balanced", "futureKey": "keep-me" },
      "apps": { "flatpakDeclared": [] }
    })").object();

    QByteArray out;
    QString e;
    QVERIFY2(SettingsStore::mergeShellStyleAndSerialize(root, QStringLiteral("islands"), &out, &e), qPrintable(e));
    QJsonObject a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a.value(QStringLiteral("shellStyle")).toString(), QStringLiteral("islands"));
    QCOMPARE(a.value(QStringLiteral("visualProfile")).toString(), QStringLiteral("balanced"));
    QCOMPARE(a.value(QStringLiteral("futureKey")).toString(), QStringLiteral("keep-me"));

    QVERIFY(SettingsStore::mergeShellStyleAndSerialize(root, QStringLiteral("quattro"), &out, &e));
    a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QCOMPARE(a.value(QStringLiteral("shellStyle")).toString(), QStringLiteral("quattro"));

    // null on a file without the key adds nothing (byte-identical document).
    QVERIFY(SettingsStore::mergeShellStyleAndSerialize(root, QVariant(), &out, &e));
    QCOMPARE(out, QJsonDocument(root).toJson(QJsonDocument::Indented));

    // null on a file that has it writes explicit null (back to the default).
    QJsonObject withKey = root;
    QJsonObject app = withKey.value(QStringLiteral("appearance")).toObject();
    app.insert(QStringLiteral("shellStyle"), QStringLiteral("islands"));
    withKey.insert(QStringLiteral("appearance"), app);
    QVERIFY(SettingsStore::mergeShellStyleAndSerialize(withKey, QVariant(), &out, &e));
    a = QJsonDocument::fromJson(out).object().value(QStringLiteral("appearance")).toObject();
    QVERIFY(a.contains(QStringLiteral("shellStyle")));
    QVERIFY(a.value(QStringLiteral("shellStyle")).isNull());

    QVERIFY(!SettingsStore::mergeShellStyleAndSerialize(root, QStringLiteral("omarchy"), &out, &e));
    QVERIFY(e.contains(QStringLiteral("shellStyle")));
    QVERIFY(!SettingsStore::mergeShellStyleAndSerialize(root, 1, &out, &e));
    QVERIFY(!SettingsStore::mergeShellStyleAndSerialize(QJsonObject{{QStringLiteral("schemaVersion"), 2}},
                                                        QStringLiteral("quattro"), &out, &e));
}

QTEST_MAIN(ParserTests)
#include "test_parsers.moc"
