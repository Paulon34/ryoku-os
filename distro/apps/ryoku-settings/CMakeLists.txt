cmake_minimum_required(VERSION 3.21)
project(ryoku-settings VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus LinguistTools Svg)

qt_standard_project_setup(REQUIRES 6.5)

qt_policy(SET QTP0004 OLD)

set(RYOKU_REPO_PATH_DEFAULT "" CACHE STRING "Default Ryoku repo path baked at build time")
set(RYOKU_FLAKE_HOST_DEFAULT "" CACHE STRING "Flake host attribute baked at build time (bootstrap hint)")

set_source_files_properties(qml/RyokuTheme.qml PROPERTIES
  QT_QML_SINGLETON_TYPE TRUE
)

qt_add_executable(ryoku-settings
  src/main.cpp
  src/RepoPath.cpp
  src/RepoPath.h
  src/LanguageManager.cpp
  src/LanguageManager.h
  src/PaletteManager.cpp
  src/PaletteManager.h
  src/SettingsStore.cpp
  src/SettingsStore.h
  src/GitStatusModel.cpp
  src/GitStatusModel.h
  src/WallpaperGalleryModel.cpp
  src/WallpaperGalleryModel.h
  src/WallpaperApplier.cpp
  src/WallpaperApplier.h
  src/FlatpakAppsModel.cpp
  src/FlatpakAppsModel.h
  src/DesktopAppsModel.cpp
  src/DesktopAppsModel.h
  src/NetworkManagerModel.cpp
  src/NetworkManagerModel.h
  src/BluetoothModel.cpp
  src/BluetoothModel.h
  src/SoundModel.cpp
  src/SoundModel.h
  src/DisplayModel.cpp
  src/DisplayModel.h
  src/PowerModel.cpp
  src/PowerModel.h
  src/ApplyController.cpp
  src/ApplyController.h
  src/SystemInfoModel.cpp
  src/SystemInfoModel.h
  src/FlakeMetadataModel.cpp
  src/FlakeMetadataModel.h
  src/FlakeUpdateModel.cpp
  src/FlakeUpdateModel.h
  src/GenerationsModel.cpp
  src/GenerationsModel.h
)

# PT-BR translations (English is the source language — no .qm).
set(RYOKU_TS_FILES
  ${CMAKE_CURRENT_SOURCE_DIR}/i18n/ryoku-settings_pt_BR.ts
)
qt_add_translations(ryoku-settings
  TS_FILES ${RYOKU_TS_FILES}
  RESOURCE_PREFIX "/i18n"
)

# Branding assets: Material Symbols subset + canonical app icon (cwd-independent).
qt_add_resources(ryoku-settings "ryoku_branding"
  PREFIX "/ryoku"
  BASE "resources"
  FILES
    resources/fonts/MaterialSymbolsRounded-Ryoku.ttf
    resources/icons/hicolor/scalable/apps/org.ryoku.Settings.svg
    resources/icons/hicolor/128x128/apps/org.ryoku.Settings.png
)

target_compile_definitions(ryoku-settings PRIVATE
  RYOKU_SETTINGS_VERSION="${PROJECT_VERSION}-dev"
  RYOKU_REPO_PATH_DEFAULT="${RYOKU_REPO_PATH_DEFAULT}"
  RYOKU_FLAKE_HOST_DEFAULT="${RYOKU_FLAKE_HOST_DEFAULT}"
)

qt_add_qml_module(ryoku-settings
  URI Ryoku.Settings
  VERSION 1.0
  QML_FILES
    qml/Main.qml
    qml/RyokuTheme.qml
    qml/components/RyokuCard.qml
    qml/components/RyokuNavItem.qml
    qml/components/RyokuIcon.qml
    qml/components/RyokuSectionTitle.qml
    qml/components/RyokuSettingRow.qml
    qml/components/RyokuBadge.qml
    qml/components/RyokuButton.qml
    qml/components/RyokuText.qml
    qml/components/RyokuPlaceholderPage.qml
    qml/components/RyokuToggle.qml
    qml/components/RyokuSlider.qml
    qml/components/RyokuDeviceRow.qml
    qml/components/RyokuComboBox.qml
    qml/components/RyokuApplyBanner.qml
    qml/components/RyokuDialog.qml
    qml/components/RyokuSearchField.qml
    qml/components/RyokuSearchIndex.qml
    qml/components/RyokuStateLayer.qml
    qml/pages/HomePage.qml
    qml/pages/AppearancePage.qml
    qml/pages/AppsPage.qml
    qml/pages/NetworkPage.qml
    qml/pages/BluetoothPage.qml
    qml/pages/SoundPage.qml
    qml/pages/DisplaysPage.qml
    qml/pages/PowerPage.qml
    qml/pages/SystemPage.qml
    qml/pages/NixUpdatesPage.qml
    qml/pages/AboutPage.qml
)

target_link_libraries(ryoku-settings PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
  Qt6::QuickControls2
  Qt6::DBus
  Qt6::Svg
)

install(TARGETS ryoku-settings
  RUNTIME DESTINATION bin
)

install(FILES resources/org.ryoku.Settings.desktop
  DESTINATION share/applications
)

# FreeDesktop icon theme — canonical name org.ryoku.Settings
install(FILES resources/icons/hicolor/scalable/apps/org.ryoku.Settings.svg
  DESTINATION share/icons/hicolor/scalable/apps
)
install(DIRECTORY resources/icons/hicolor/
  DESTINATION share/icons/hicolor
  FILES_MATCHING
    PATTERN "org.ryoku.Settings.png"
    PATTERN "org.ryoku.Settings.svg"
)

option(RYOKU_SETTINGS_BUILD_TESTS "Build parser unit tests" ON)
if(RYOKU_SETTINGS_BUILD_TESTS)
  enable_language(C)
  find_package(Qt6 REQUIRED COMPONENTS Test)
  set(RYOKU_APPLY_OPS_SRC
    "${CMAKE_CURRENT_SOURCE_DIR}/../ryoku-settings-apply/src/ops.c")
  set(RYOKU_APPLY_OPS_INC
    "${CMAKE_CURRENT_SOURCE_DIR}/../ryoku-settings-apply/src")
  qt_add_executable(ryoku-settings-tests
    tests/test_parsers.cpp
    src/PaletteManager.cpp
    src/PaletteManager.h
    src/SettingsStore.cpp
    src/SettingsStore.h
    src/RepoPath.cpp
    src/RepoPath.h
    src/LanguageManager.cpp
    src/LanguageManager.h
    src/GitStatusModel.cpp
    src/GitStatusModel.h
    src/WallpaperGalleryModel.cpp
    src/WallpaperGalleryModel.h
    src/WallpaperApplier.cpp
    src/WallpaperApplier.h
    src/FlatpakAppsModel.cpp
    src/FlatpakAppsModel.h
    src/NetworkManagerModel.cpp
    src/NetworkManagerModel.h
    src/BluetoothModel.cpp
    src/BluetoothModel.h
    src/SoundModel.cpp
    src/SoundModel.h
    src/DisplayModel.cpp
    src/DisplayModel.h
    src/PowerModel.cpp
    src/PowerModel.h
    src/ApplyController.cpp
    src/ApplyController.h
    src/SystemInfoModel.cpp
    src/SystemInfoModel.h
    src/FlakeMetadataModel.cpp
    src/FlakeMetadataModel.h
    src/FlakeUpdateModel.cpp
    src/FlakeUpdateModel.h
    src/GenerationsModel.cpp
    src/GenerationsModel.h
  )
  target_sources(ryoku-settings-tests PRIVATE ${RYOKU_APPLY_OPS_SRC})
  target_compile_definitions(ryoku-settings-tests PRIVATE
    RYOKU_SETTINGS_VERSION="${PROJECT_VERSION}-dev"
    RYOKU_REPO_PATH_DEFAULT=""
    RYOKU_SETTINGS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
  )
  target_include_directories(ryoku-settings-tests PRIVATE
    src
    ${RYOKU_APPLY_OPS_INC}
  )
  target_link_libraries(ryoku-settings-tests PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Qml
    Qt6::DBus
    Qt6::Test
  )
endif()
