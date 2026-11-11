import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    readonly property bool wide: width >= 720

    readonly property string configStatus: {
        const w = Window.window
        if (w && w.ryokuConfigStatus !== undefined)
            return w.ryokuConfigStatus
        if (!settingsStore.loaded)
            return qsTr("Error")
        return qsTr("Clean")
    }

    readonly property string configKind: {
        const s = root.configStatus
        if (s === qsTr("Error") || s === qsTr("Hash error")
            || s.indexOf(qsTr("failed")) >= 0)
            return "error"
        if (s === qsTr("Needs Apply") || s === qsTr("Unsaved"))
            return "needs_apply"
        if (s === qsTr("Applied"))
            return "applied"
        if (s.indexOf(qsTr("Waiting")) >= 0 || s.indexOf(qsTr("Applying")) >= 0
            || s.indexOf(qsTr("Resolving")) >= 0 || s.indexOf(qsTr("Switching")) >= 0
            || s.indexOf(qsTr("Rolling")) >= 0)
            return "current"
        return "neutral"
    }

    readonly property string applyKind: {
        const st = applyController.status
        if (st === "ApplyFailed" || st === "RollbackFailed" || st === "SwitchFailed"
            || st === "HashError" || st === "AuthorizationError")
            return "error"
        if (st === "Applied")
            return "applied"
        if (st === "NeedsApply" || st === "Ready" || st === "ValidationFailed"
            || st === "AuthorizationDenied")
            return "needs_apply"
        if (applyController.busy)
            return "current"
        return "neutral"
    }

    readonly property string gitKind: {
        if (!gitStatus.available)
            return "neutral"
        if (gitStatus.error.length)
            return "error"
        if (gitStatus.clean)
            return "applied"
        return "modified"
    }

    readonly property string wifiLine: {
        if (!networkModel.available)
            return qsTr("Unavailable")
        if (networkModel.connectedSsid.length)
            return qsTr("Connected · %1").arg(networkModel.connectedSsid)
        return networkModel.connectivityLabel
    }

    readonly property string bluetoothLine: {
        if (!bluetoothModel.available)
            return qsTr("Unavailable")
        if (!bluetoothModel.powered)
            return qsTr("Off")
        const n = bluetoothModel.connectedCount
        if (n <= 0)
            return qsTr("On · No devices")
        return n === 1 ? qsTr("On · 1 device") : qsTr("On · %1 devices").arg(n)
    }

    readonly property string soundLine: {
        if (!soundModel.available)
            return qsTr("Unavailable")
        if (soundModel.outputMuted)
            return qsTr("Muted")
        return qsTr("%1%").arg(soundModel.outputVolume)
    }

    readonly property string batteryLine: {
        if (!powerModel.batteryAvailable)
            return qsTr("Unavailable")
        if (!powerModel.batteryPresent)
            return qsTr("No battery")
        return qsTr("%1% · %2")
            .arg(Math.round(powerModel.batteryPercentage))
            .arg(powerModel.batteryStateLabel)
    }

    readonly property string displaysLine: {
        if (!displayModel.available)
            return qsTr("Unavailable")
        const n = displayModel.count
        return n === 1 ? qsTr("1 connected") : qsTr("%1 connected").arg(n)
    }

    readonly property string powerProfileLine: {
        if (!powerModel.profilesAvailable)
            return qsTr("Unavailable")
        const id = powerModel.activeProfile
        if (!id.length)
            return qsTr("Unavailable")
        const list = powerModel.profiles
        for (let i = 0; i < list.length; ++i) {
            const row = list[i]
            if (row && (row.id === id || row.active === true) && row.name)
                return row.name
        }
        return id
    }

    readonly property string generationLine: {
        const g = systemInfo.profileGeneration
        if (g > 0)
            return qsTr("Generation %1").arg(g)
        const cg = generationsModel.currentGeneration
        if (cg > 0)
            return qsTr("Generation %1").arg(cg)
        return qsTr("Unavailable")
    }

    property string greeting: qsTr("Welcome back")

    function updateGreeting() {
        const h = new Date().getHours()
        if (h < 12)
            greeting = qsTr("Good morning")
        else if (h < 18)
            greeting = qsTr("Good afternoon")
        else
            greeting = qsTr("Good evening")
    }

    function goTo(pageIndex) {
        const w = Window.window
        if (w)
            w.currentIndex = pageIndex
    }

    Component.onCompleted: {
        updateGreeting()
        flatpakApps.refresh()
    }

    Connections {
        target: languageManager
        function onLanguageChanged() { root.updateGreeting() }
    }

    // Compact status row used inside overview cards
    component StatusLine: RowLayout {
        property string title: ""
        property string value: ""
        property string badgeText: ""
        property string badgeKind: "neutral"
        spacing: RyokuTheme.spacing_sm
        width: parent ? parent.width : 200

        Column {
            Layout.fillWidth: true
            spacing: 2
            Text {
                width: parent.width
                text: title
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }
            Text {
                width: parent.width
                text: value
                color: RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                font.bold: true
                wrapMode: Text.WordWrap
            }
        }
        RyokuBadge {
            visible: badgeText.length > 0
            text: badgeText
            kind: badgeKind
        }
    }

    component QuickTile: Item {
        id: tile
        property string title: ""
        property string subtitle: ""
        property string glyph: ""
        property int pageIndex: 0
        signal activated

        implicitHeight: 72
        Layout.fillWidth: true
        Layout.preferredWidth: root.wide ? 160 : parent.width

        Rectangle {
            anchors.fill: parent
            radius: RyokuTheme.radius_md
            color: tileHover.hovered ? RyokuTheme.primary_tint : RyokuTheme.glass_surface_high
            border.width: RyokuTheme.border_width
            border.color: tileHover.hovered
                          ? Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.40)
                          : RyokuTheme.glass_border
            Behavior on color { ColorAnimation { duration: RyokuTheme.animation_fast } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: RyokuTheme.spacing_sm
                spacing: RyokuTheme.spacing_sm

                Text {
                    text: tile.glyph
                    color: RyokuTheme.primary
                    font.pixelSize: RyokuTheme.font_section
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignHCenter
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        width: parent.width
                        text: tile.title
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: tile.subtitle
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        elide: Text.ElideRight
                    }
                }
            }
        }

        HoverHandler { id: tileHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                tile.activated()
                root.goTo(tile.pageIndex)
            }
        }
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: RyokuTheme.spacing_md

        // ── Hero ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border
            implicitHeight: heroCol.implicitHeight + RyokuTheme.spacing_md * 2
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * 0.55
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.14)
                    }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: RyokuTheme.radius_sm
                anchors.rightMargin: RyokuTheme.radius_sm
                height: 1
                color: RyokuTheme.glass_highlight
            }

            ColumnLayout {
                id: heroCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: RyokuTheme.spacing_md
                spacing: RyokuTheme.spacing_xs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: RyokuTheme.spacing_sm
                    Text {
                        text: qsTr("Ryoku")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_title
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    RyokuBadge {
                        text: root.configStatus
                        kind: root.configKind
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.greeting
                    color: RyokuTheme.primary
                    font.pixelSize: RyokuTheme.font_section
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Your system at a glance")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_body
                }

                Text {
                    Layout.fillWidth: true
                    visible: systemInfo.hostname.length > 0
                    text: systemInfo.hostname
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        Text {
            visible: paletteManager.warning.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Palette: %1").arg(paletteManager.warning)
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── System + Connectivity ─────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: root.wide ? 2 : 1
            columnSpacing: RyokuTheme.spacing_md
            rowSpacing: RyokuTheme.spacing_md

            RyokuCard {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? parent.width / 2 - RyokuTheme.spacing_md / 2 : parent.width
                title: qsTr("System state")

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_md

                    StatusLine {
                        title: qsTr("Apply")
                        value: applyController.statusText
                        badgeText: applyController.needsSystemApply && applyController.status !== "Applied"
                                   ? qsTr("Needs Apply") : ""
                        badgeKind: root.applyKind
                    }

                    StatusLine {
                        title: qsTr("Generation")
                        value: root.generationLine
                        badgeText: systemInfo.generationPathsMatch ? qsTr("Current") : ""
                        badgeKind: "current"
                    }

                    Column {
                        width: parent.width
                        spacing: RyokuTheme.spacing_xs
                        RowLayout {
                            width: parent.width
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Git")
                                color: RyokuTheme.on_surface_muted
                                font.pixelSize: RyokuTheme.font_caption
                            }
                            RyokuButton {
                                text: qsTr("Refresh")
                                variant: "ghost"
                                onClicked: gitStatus.refresh()
                            }
                        }
                        RowLayout {
                            width: parent.width
                            spacing: RyokuTheme.spacing_sm
                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: gitStatus.available
                                          ? gitStatus.workingTreeLabel
                                          : qsTr("Unavailable")
                                    color: RyokuTheme.on_surface
                                    font.pixelSize: RyokuTheme.font_body
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    visible: gitStatus.available && gitStatus.branch.length > 0
                                    width: parent.width
                                    text: gitStatus.branch
                                    color: RyokuTheme.on_surface_muted
                                    font.pixelSize: RyokuTheme.font_caption
                                    elide: Text.ElideMiddle
                                }
                            }
                            RyokuBadge {
                                visible: gitStatus.available
                                text: gitStatus.clean ? qsTr("Clean") : qsTr("Modified")
                                kind: root.gitKind
                            }
                        }
                        Text {
                            visible: gitStatus.error.length > 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: gitStatus.error
                            color: RyokuTheme.error
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                }
            }

            RyokuCard {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? parent.width / 2 - RyokuTheme.spacing_md / 2 : parent.width
                title: qsTr("Connectivity")

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_md

                    StatusLine {
                        title: qsTr("Wi-Fi")
                        value: root.wifiLine
                    }
                    StatusLine {
                        title: qsTr("Bluetooth")
                        value: root.bluetoothLine
                    }
                    StatusLine {
                        title: qsTr("Sound")
                        value: root.soundLine
                    }
                    Text {
                        visible: soundModel.available && soundModel.defaultOutputName.length > 0
                        width: parent.width
                        text: soundModel.defaultOutputName
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        // ── Device ────────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Device")

            GridLayout {
                width: parent.width
                columns: root.wide ? 3 : 1
                columnSpacing: RyokuTheme.spacing_md
                rowSpacing: RyokuTheme.spacing_md

                StatusLine {
                    Layout.fillWidth: true
                    title: qsTr("Battery")
                    value: root.batteryLine
                }
                StatusLine {
                    Layout.fillWidth: true
                    title: qsTr("Displays")
                    value: root.displaysLine
                }
                StatusLine {
                    Layout.fillWidth: true
                    title: qsTr("Power profile")
                    value: root.powerProfileLine
                }
            }
        }

        // ── Quick navigation ──────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Quick access")

            GridLayout {
                width: parent.width
                columns: root.wide ? 4 : 2
                columnSpacing: RyokuTheme.spacing_sm
                rowSpacing: RyokuTheme.spacing_sm

                QuickTile {
                    title: qsTr("Appearance")
                    subtitle: settingsStore.wallpaper.length
                              ? settingsStore.wallpaper
                              : qsTr("Look & feel")
                    glyph: "◐"
                    pageIndex: 1
                }
                QuickTile {
                    title: qsTr("Apps")
                    subtitle: qsTr("%1 managed").arg(settingsStore.flatpakDeclaredCount)
                    glyph: "▦"
                    pageIndex: 7
                }
                QuickTile {
                    title: qsTr("Nix & Updates")
                    subtitle: qsTr("Flake · Git · Generations")
                    glyph: "❄"
                    pageIndex: 9
                }
                QuickTile {
                    title: qsTr("System")
                    subtitle: systemInfo.osPrettyName.length
                              ? systemInfo.osPrettyName
                              : qsTr("Host details")
                    glyph: "⚙"
                    pageIndex: 8
                }
            }
        }
    }
}
