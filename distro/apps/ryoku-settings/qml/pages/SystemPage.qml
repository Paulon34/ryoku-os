import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    readonly property bool wide: width >= 720

    Component.onCompleted: systemInfo.refresh()

    function refreshAll() {
        systemInfo.refresh()
    }

    function shortPath(p) {
        if (!p || !p.length)
            return qsTr("Unavailable")
        const parts = p.split("/")
        if (parts.length <= 3)
            return p
        return "…/" + parts.slice(-3).join("/")
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: RyokuTheme.spacing_md

        // ── Header ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: RyokuTheme.spacing_xxs
            RowLayout {
                Layout.fillWidth: true
                spacing: RyokuTheme.spacing_sm
                Text {
                    Layout.fillWidth: true
                    text: qsTr("System")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                }
                RyokuButton {
                    text: qsTr("Refresh")
                    variant: "ghost"
                    onClicked: root.refreshAll()
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Hardware and operating system information")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
            Text {
                Layout.fillWidth: true
                visible: systemInfo.osPrettyName.length > 0
                wrapMode: Text.WordWrap
                text: qsTr("Ryoku · %1").arg(systemInfo.osPrettyName)
                color: RyokuTheme.primary
                font.pixelSize: RyokuTheme.font_section
                font.bold: true
            }
        }

        Text {
            visible: systemInfo.lastError.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: systemInfo.lastError
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── OS + Session ──────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: root.wide ? 2 : 1
            columnSpacing: RyokuTheme.spacing_md
            rowSpacing: RyokuTheme.spacing_md

            RyokuCard {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? parent.width / 2 - RyokuTheme.spacing_md / 2 : parent.width
                title: qsTr("Operating system")

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    RyokuSettingRow {
                        // Prefer PRETTY_NAME alone — VERSION is usually already embedded.
                        label: qsTr("Operating system")
                        value: {
                            if (systemInfo.osPrettyName.length
                                && systemInfo.osPrettyName !== "Unavailable")
                                return systemInfo.osPrettyName
                            if (systemInfo.osVersion.length)
                                return systemInfo.osVersion
                            return qsTr("Unavailable")
                        }
                    }
                    RyokuSettingRow {
                        label: qsTr("Kernel")
                        value: systemInfo.kernel.length ? systemInfo.kernel : qsTr("Unavailable")
                    }
                    RyokuSettingRow {
                        label: qsTr("Hostname")
                        value: systemInfo.hostname.length ? systemInfo.hostname : qsTr("Unavailable")
                    }
                    RyokuSettingRow {
                        label: qsTr("Architecture")
                        value: systemInfo.architecture.length ? systemInfo.architecture : qsTr("Unavailable")
                    }
                }
            }

            RyokuCard {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? parent.width / 2 - RyokuTheme.spacing_md / 2 : parent.width
                title: qsTr("Session")

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    RyokuSettingRow {
                        label: qsTr("Desktop")
                        value: {
                            const parts = []
                            if (systemInfo.desktopShell.length)
                                parts.push(systemInfo.desktopShell)
                            if (systemInfo.sessionType.length)
                                parts.push(systemInfo.sessionType)
                            return parts.length ? parts.join(" · ") : qsTr("Unavailable")
                        }
                        hint: systemInfo.hyprlandVersion.length
                              ? qsTr("Hyprland %1").arg(systemInfo.hyprlandVersion)
                              : ""
                    }
                    RyokuSettingRow {
                        label: qsTr("Uptime")
                        value: systemInfo.uptimeLabel.length ? systemInfo.uptimeLabel : qsTr("Unavailable")
                    }
                }
            }
        }

        // ── Hardware ──────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Hardware")

            GridLayout {
                width: parent.width
                columns: root.wide ? 2 : 1
                columnSpacing: RyokuTheme.spacing_md
                rowSpacing: RyokuTheme.spacing_sm

                RyokuSettingRow {
                    Layout.fillWidth: true
                    label: qsTr("Processor")
                    value: systemInfo.cpuModel.length ? systemInfo.cpuModel : qsTr("Unavailable")
                }
                RyokuSettingRow {
                    Layout.fillWidth: true
                    label: qsTr("Memory")
                    value: systemInfo.memoryTotalLabel.length ? systemInfo.memoryTotalLabel : qsTr("Unavailable")
                }

                // Graphics IDs stay available but as secondary technical detail.
                Column {
                    Layout.fillWidth: true
                    Layout.columnSpan: root.wide ? 2 : 1
                    spacing: RyokuTheme.spacing_xxs
                    Text {
                        width: parent.width
                        text: qsTr("Graphics")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: systemInfo.gpuLabels.length
                              ? systemInfo.gpuLabels.join("\n")
                              : qsTr("Unavailable")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                }

                RyokuSettingRow {
                    Layout.fillWidth: true
                    Layout.columnSpan: root.wide ? 2 : 1
                    label: qsTr("Battery")
                    value: systemInfo.batterySummary.length
                           ? systemInfo.batterySummary
                           : qsTr("Unavailable")
                }
            }
        }

        // ── Generation ────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Generation")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                RowLayout {
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: systemInfo.profileGeneration >= 0
                              ? qsTr("Generation %1").arg(systemInfo.profileGeneration)
                              : qsTr("Generation unavailable")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_section
                        font.bold: true
                    }
                    RyokuBadge {
                        text: systemInfo.generationPathsMatch
                              ? qsTr("Current")
                              : (systemInfo.generationMatchLabel.length
                                 ? systemInfo.generationMatchLabel
                                 : qsTr("Mismatch"))
                        kind: systemInfo.generationPathsMatch ? "current" : "modified"
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: systemInfo.profileLinkName.length
                          ? systemInfo.profileLinkName
                          : qsTr("System profile")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                RyokuSettingRow {
                    label: qsTr("Current system")
                    value: root.shortPath(systemInfo.currentSystemPath)
                    hint: systemInfo.currentSystemPath
                }
                RyokuSettingRow {
                    label: qsTr("Profile system")
                    value: root.shortPath(systemInfo.profileSystemPath)
                    hint: systemInfo.profileSystemPath
                }
            }
        }
    }
}
