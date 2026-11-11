import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    readonly property string displayRepo: {
        if (!repoPath || !repoPath.length)
            return qsTr("Unavailable")
        // Compact home-relative form when path is under /home/<user>/...
        const homePrefix = "/home/"
        if (repoPath.indexOf(homePrefix) === 0) {
            const rest = repoPath.slice(homePrefix.length)
            const slash = rest.indexOf("/")
            if (slash > 0)
                return "~" + rest.slice(slash)
        }
        return repoPath
    }

    readonly property string environmentLine: {
        const parts = []
        if (systemInfo && systemInfo.osPrettyName && systemInfo.osPrettyName.length
            && systemInfo.osPrettyName !== "Unavailable")
            parts.push(systemInfo.osPrettyName)
        else
            parts.push("NixOS")
        if (systemInfo && systemInfo.desktopShell && systemInfo.desktopShell.length)
            parts.push(systemInfo.desktopShell)
        else if (systemInfo && systemInfo.sessionType && systemInfo.sessionType.length)
            parts.push(systemInfo.sessionType)
        else
            parts.push("Hyprland")
        return parts.join(" · ")
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: RyokuTheme.spacing_md

        // ── Hero ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            radius: RyokuTheme.radius_xl
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border
            implicitHeight: heroCol.implicitHeight + RyokuTheme.spacing_xl
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.16)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.rgba(RyokuTheme.secondary.r, RyokuTheme.secondary.g, RyokuTheme.secondary.b, 0.06)
                    }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: RyokuTheme.radius_md
                anchors.rightMargin: RyokuTheme.radius_md
                height: 1
                color: RyokuTheme.glass_highlight
            }

            ColumnLayout {
                id: heroCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: RyokuTheme.spacing_lg
                spacing: RyokuTheme.spacing_sm

                // Canonical app icon (org.ryoku.Settings).
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    width: RyokuTheme.icon_size_lg + 24
                    height: RyokuTheme.icon_size_lg + 24
                    source: "qrc:/ryoku/icons/hicolor/128x128/apps/org.ryoku.Settings.png"
                    sourceSize.width: 128
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: appDisplayName.length ? appDisplayName : qsTr("Ryoku Settings")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_display
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Ryoku Desktop Experience")
                    color: RyokuTheme.primary
                    font.pixelSize: RyokuTheme.font_section
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: appVersion.length ? qsTr("Version %1").arg(appVersion) : qsTr("Version —")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: RyokuTheme.spacing_xs
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("A modern, declarative desktop experience\nbuilt on NixOS and Hyprland.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_body
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: RyokuTheme.spacing_xs
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Declarative. Dynamic. Personal.")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_caption
                    font.bold: true
                }
            }
        }

        // ── Application ───────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Application")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                RyokuSettingRow {
                    label: qsTr("Application")
                    value: appDisplayName.length ? appDisplayName : qsTr("Ryoku Settings")
                }
                RyokuSettingRow {
                    label: qsTr("App ID")
                    value: appId.length ? appId : qsTr("Unavailable")
                }
                RyokuSettingRow {
                    label: qsTr("Version")
                    value: appVersion.length ? appVersion : qsTr("Unavailable")
                }
                RyokuSettingRow {
                    label: qsTr("Desktop")
                    value: qsTr("Ryoku")
                }
                RyokuSettingRow {
                    label: qsTr("Environment")
                    value: root.environmentLine
                }
                RyokuSettingRow {
                    label: qsTr("Settings schema")
                    value: settingsReader.loaded
                           ? String(settingsReader.schemaVersion)
                           : qsTr("—")
                }
            }
        }

        // ── Repository & technology ───────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Repository & stack")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xxs
                    Text {
                        width: parent.width
                        text: qsTr("Repository")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    Text {
                        width: parent.width
                        text: root.displayRepo
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                        elide: Text.ElideMiddle
                        wrapMode: Text.WrapAnywhere
                    }
                    Text {
                        width: parent.width
                        visible: repoPath.length > 0 && root.displayRepo !== repoPath
                        text: repoPath
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        wrapMode: Text.WrapAnywhere
                        elide: Text.ElideMiddle
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    Text {
                        text: qsTr("Built with")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    Flow {
                        width: parent.width
                        spacing: RyokuTheme.spacing_xs
                        Repeater {
                            model: [
                                qsTr("NixOS"),
                                qsTr("Hyprland"),
                                qsTr("Qt %1").arg(qtRuntimeVersion.length ? qtRuntimeVersion : "6"),
                                qsTr("QML"),
                                qsTr("Home Manager")
                            ]
                            delegate: Rectangle {
                                required property string modelData
                                implicitHeight: 28
                                implicitWidth: chipLabel.implicitWidth + RyokuTheme.spacing_md
                                radius: RyokuTheme.radius_pill
                                color: RyokuTheme.glass_surface_high
                                border.width: RyokuTheme.border_width
                                border.color: RyokuTheme.glass_border
                                Text {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: RyokuTheme.on_surface_muted
                                    font.pixelSize: RyokuTheme.font_caption
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Standalone settings app — external to the shell panel.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }
    }
}
