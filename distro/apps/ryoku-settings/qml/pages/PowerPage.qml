import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    property string statusMessage: ""
    readonly property bool wide: width >= 720

    readonly property string batteryHeadline: {
        if (!powerModel.batteryAvailable)
            return qsTr("Unavailable")
        if (!powerModel.batteryPresent)
            return qsTr("No battery")
        return Math.round(powerModel.batteryPercentage) + "%"
    }

    readonly property string batteryStateHuman: {
        const s = powerModel.batteryStateLabel
        if (s === "Full")
            return qsTr("Fully charged")
        if (s === "Charging")
            return qsTr("Charging")
        if (s === "Discharging")
            return qsTr("Discharging")
        if (s === "Empty")
            return qsTr("Empty")
        if (s === "Pending charge")
            return qsTr("Pending charge")
        if (s === "Pending discharge")
            return qsTr("Pending discharge")
        if (s === "No battery")
            return qsTr("No battery")
        if (s === "Unknown" || !s.length)
            return qsTr("AC power")
        return s
    }

    readonly property string headerBadge: {
        if (!powerModel.batteryAvailable)
            return qsTr("Power")
        if (!powerModel.batteryPresent)
            return qsTr("AC power")
        return qsTr("Battery %1%").arg(Math.round(powerModel.batteryPercentage))
    }

    readonly property string lidLabelHuman: {
        const s = powerModel.lidBehaviorLabel
        if (s === "Ignore (declarative)")
            return qsTr("Ignore (declarative)")
        return s
    }

    readonly property string suspendLabelHuman: {
        const s = powerModel.suspendLabel
        if (s === "System default (declarative)")
            return qsTr("System default (declarative)")
        if (s.startsWith("Idle action: "))
            return qsTr("Idle action: %1").arg(s.slice("Idle action: ".length))
        return s
    }

    readonly property string idleLabelHuman: {
        const s = powerModel.idleLabel
        if (s === "hypridle installed (declarative)")
            return qsTr("hypridle installed (declarative)")
        return s
    }

    Connections {
        target: powerModel
        function onOperationFailed(message) { root.statusMessage = message }
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
                    text: qsTr("Power")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                    Layout.fillWidth: true
                }
                RyokuBadge {
                    text: root.headerBadge
                    kind: powerModel.batteryPresent ? "current" : "neutral"
                }
                RyokuButton {
                    text: qsTr("Refresh")
                    variant: "ghost"
                    onClicked: powerModel.refresh()
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Battery, brightness and power behavior")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.statusMessage.length > 0
            wrapMode: Text.WordWrap
            text: root.statusMessage
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── Battery + Brightness (side by side when wide) ─────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: root.wide ? 2 : 1
            columnSpacing: RyokuTheme.spacing_md
            rowSpacing: RyokuTheme.spacing_md

            RyokuCard {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? parent.width / 2 - RyokuTheme.spacing_md / 2 : parent.width
                title: qsTr("Battery")

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_md

                    Text {
                        width: parent.width
                        visible: !powerModel.batteryAvailable
                        wrapMode: Text.WordWrap
                        text: powerModel.batteryError.length
                              ? (powerModel.batteryError === "UPower unavailable"
                                 ? qsTr("UPower unavailable")
                                 : powerModel.batteryError)
                              : qsTr("UPower unavailable")
                        color: RyokuTheme.error
                        font.pixelSize: RyokuTheme.font_caption
                    }

                    Text {
                        width: parent.width
                        visible: powerModel.batteryAvailable && !powerModel.batteryPresent
                        wrapMode: Text.WordWrap
                        text: qsTr("No battery detected")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_body
                    }

                    Column {
                        width: parent.width
                        visible: powerModel.batteryPresent
                        spacing: RyokuTheme.spacing_sm

                        RowLayout {
                            width: parent.width
                            Text {
                                text: root.batteryHeadline
                                color: RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_display
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            RyokuBadge {
                                text: root.batteryStateHuman
                                kind: powerModel.batteryStateLabel === "Charging" ? "applied"
                                    : (powerModel.batteryStateLabel === "Discharging" ? "modified" : "current")
                            }
                        }

                        // Simple level bar — no shader / no history chart
                        Rectangle {
                            width: parent.width
                            height: 10
                            radius: 5
                            color: RyokuTheme.glass_surface_high
                            border.width: RyokuTheme.border_width
                            border.color: RyokuTheme.glass_border

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 2
                                width: Math.max(0, (parent.width - 4)
                                               * Math.max(0, Math.min(1, powerModel.batteryPercentage / 100)))
                                radius: 3
                                color: powerModel.batteryPercentage <= 15
                                       ? RyokuTheme.error
                                       : RyokuTheme.primary
                            }
                        }

                        Text {
                            width: parent.width
                            visible: powerModel.batteryTimeLabel.length > 0
                            wrapMode: Text.WordWrap
                            text: powerModel.batteryTimeLabel
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                        Text {
                            width: parent.width
                            visible: powerModel.energyRateValid
                            wrapMode: Text.WordWrap
                            text: qsTr("%1 W").arg(powerModel.energyRate.toFixed(1))
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                }
            }

            RyokuCard {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? parent.width / 2 - RyokuTheme.spacing_md / 2 : parent.width
                title: qsTr("Brightness")

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_md

                    Text {
                        width: parent.width
                        visible: !powerModel.brightnessAvailable
                        wrapMode: Text.WordWrap
                        text: powerModel.brightnessError.length
                              ? powerModel.brightnessError
                              : qsTr("Brightness unavailable on this device")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }

                    Column {
                        width: parent.width
                        visible: powerModel.brightnessAvailable
                        spacing: RyokuTheme.spacing_xs

                        RowLayout {
                            width: parent.width
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Display brightness")
                                color: RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_body
                                font.bold: true
                            }
                            Text {
                                text: powerModel.brightness + "%"
                                color: RyokuTheme.primary
                                font.pixelSize: RyokuTheme.font_body
                                font.bold: true
                            }
                        }

                        RyokuSlider {
                            width: parent.width
                            from: 1
                            to: 100
                            value: powerModel.brightness
                            stepSize: 1
                            formatValue: function(v) { return Math.round(v) + "%" }
                            onMoved: function(v) { powerModel.scheduleBrightness(Math.round(v)) }
                        }
                    }
                }
            }
        }

        // ── Power profile ─────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Power profile")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                Column {
                    width: parent.width
                    visible: !powerModel.profilesAvailable
                    spacing: RyokuTheme.spacing_xs
                    Text {
                        width: parent.width
                        text: qsTr("Unavailable")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: powerModel.profilesError.length
                              ? powerModel.profilesError
                              : qsTr("power-profiles-daemon is not enabled on this system.")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                }

                Repeater {
                    model: powerModel.profiles
                    delegate: RyokuDeviceRow {
                        required property var modelData
                        width: parent.width
                        leadingIcon: {
                            const id = String(modelData.id || "")
                            if (id === "power-saver" || id === "power_saver")
                                return "battery_saver"
                            if (id === "performance")
                                return "speed"
                            return "tune"
                        }
                        title: {
                            const id = String(modelData.id || "")
                            if (id === "power-saver" || id === "power_saver")
                                return qsTr("Power Saver")
                            if (id === "balanced")
                                return qsTr("Balanced")
                            if (id === "performance")
                                return qsTr("Performance")
                            return modelData.name
                        }
                        subtitle: modelData.active ? qsTr("Active") : qsTr("Available")
                        badgeText: modelData.active ? qsTr("Current") : ""
                        badgeKind: "current"
                        highlighted: modelData.active
                        actionLabel: qsTr("Use")
                        actionVariant: "tonal"
                        showAction: !modelData.active
                        onActionClicked: powerModel.setPowerProfile(modelData.id)
                    }
                }
            }
        }

        // ── Sleep & lid (read-only) ───────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Sleep & lid")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Read-only hints from the current system configuration.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                RyokuSettingRow {
                    label: qsTr("Lid close")
                    value: root.lidLabelHuman
                }
                RyokuSettingRow {
                    label: qsTr("Suspend")
                    value: root.suspendLabelHuman
                }
                RyokuSettingRow {
                    label: qsTr("Idle")
                    value: root.idleLabelHuman
                }
            }
        }
    }
}
