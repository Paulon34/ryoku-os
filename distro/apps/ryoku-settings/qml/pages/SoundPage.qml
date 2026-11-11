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

    Component.onCompleted: soundModel.refresh()

    Connections {
        target: soundModel
        function onOperationFailed(message) { root.statusMessage = message }
    }

    function friendlyDeviceName(name) {
        if (!name || !name.length)
            return qsTr("Unknown device")
        // Prefer the shorter leading phrase when PipeWire returns "Nice Name - Long Chipset…"
        const parts = name.split(" - ")
        if (parts.length > 1 && parts[0].length > 0 && parts[0].length < 48)
            return parts[0]
        return name
    }

    function deviceDetail(name) {
        if (!name || !name.length)
            return ""
        const parts = name.split(" - ")
        if (parts.length > 1)
            return parts.slice(1).join(" - ")
        return ""
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
                    text: qsTr("Sound")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                    Layout.fillWidth: true
                }
                RyokuBadge {
                    text: !soundModel.available ? qsTr("Unavailable")
                          : (soundModel.outputMuted ? qsTr("Muted") : (soundModel.outputVolume + "%"))
                    kind: !soundModel.available ? "error"
                          : (soundModel.outputMuted ? "modified" : "current")
                }
                RyokuButton {
                    text: qsTr("Refresh")
                    variant: "ghost"
                    onClicked: soundModel.refresh()
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Output, input and volume")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !soundModel.available || soundModel.error.length > 0
            wrapMode: Text.WordWrap
            text: soundModel.error.length ? soundModel.error : qsTr("PipeWire unavailable")
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }
        Text {
            Layout.fillWidth: true
            visible: root.statusMessage.length > 0
            wrapMode: Text.WordWrap
            text: root.statusMessage
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── Output ────────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Output")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xxs
                    Text {
                        width: parent.width
                        text: root.friendlyDeviceName(soundModel.defaultOutputName)
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_section
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: root.deviceDetail(soundModel.defaultOutputName).length > 0
                        text: root.deviceDetail(soundModel.defaultOutputName)
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        elide: Text.ElideMiddle
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Volume")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            text: soundModel.outputVolume + "%"
                            color: soundModel.outputMuted ? RyokuTheme.on_surface_muted : RyokuTheme.primary
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                    }
                    RyokuSlider {
                        width: parent.width
                        from: 0
                        to: 100
                        value: soundModel.outputVolume
                        enabled: soundModel.available && !soundModel.outputMuted
                        formatValue: function(v) { return Math.round(v) + "%" }
                        onMoved: function(v) { soundModel.scheduleOutputVolume(Math.round(v)) }
                    }
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Mute")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                        RyokuToggle {
                            checked: soundModel.outputMuted
                            enabled: soundModel.available
                            onToggled: function(v) { soundModel.setOutputMuted(v) }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: qsTr("Devices")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_secondary
                    font.bold: true
                }

                Repeater {
                    model: soundModel.sinkDevices
                    delegate: RyokuDeviceRow {
                        required property var modelData
                        width: parent.width
                        leadingIcon: "volume_up"
                        title: root.friendlyDeviceName(modelData.name)
                        subtitle: {
                            const detail = root.deviceDetail(modelData.name)
                            if (modelData.isDefault)
                                return detail.length ? qsTr("Current · %1").arg(detail) : qsTr("Current")
                            return detail.length ? detail : qsTr("Output")
                        }
                        badgeText: modelData.isDefault ? qsTr("Current") : ""
                        badgeKind: "current"
                        highlighted: modelData.isDefault
                        actionLabel: qsTr("Use")
                        actionVariant: "tonal"
                        showAction: !modelData.isDefault
                        onActionClicked: soundModel.setDefaultSink(modelData.nodeId)
                    }
                }

                Text {
                    visible: soundModel.available && soundModel.sinkDevices.length === 0
                    width: parent.width
                    text: qsTr("No output devices available")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        // ── Input ─────────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Input")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xxs
                    Text {
                        width: parent.width
                        text: root.friendlyDeviceName(soundModel.defaultInputName)
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_section
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: root.deviceDetail(soundModel.defaultInputName).length > 0
                        text: root.deviceDetail(soundModel.defaultInputName)
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        elide: Text.ElideMiddle
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Input volume")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            text: soundModel.inputVolume + "%"
                            color: soundModel.inputMuted ? RyokuTheme.on_surface_muted : RyokuTheme.primary
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                    }
                    RyokuSlider {
                        width: parent.width
                        from: 0
                        to: 100
                        value: soundModel.inputVolume
                        enabled: soundModel.available && !soundModel.inputMuted
                        formatValue: function(v) { return Math.round(v) + "%" }
                        onMoved: function(v) { soundModel.scheduleInputVolume(Math.round(v)) }
                    }
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Mute")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                        RyokuToggle {
                            checked: soundModel.inputMuted
                            enabled: soundModel.available
                            onToggled: function(v) { soundModel.setInputMuted(v) }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: qsTr("Devices")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_secondary
                    font.bold: true
                }

                Repeater {
                    model: soundModel.sourceDevices
                    delegate: RyokuDeviceRow {
                        required property var modelData
                        width: parent.width
                        leadingIcon: "mic"
                        title: root.friendlyDeviceName(modelData.name)
                        subtitle: {
                            const detail = root.deviceDetail(modelData.name)
                            if (modelData.isDefault)
                                return detail.length ? qsTr("Current · %1").arg(detail) : qsTr("Current")
                            return detail.length ? detail : qsTr("Input")
                        }
                        badgeText: modelData.isDefault ? qsTr("Current") : ""
                        badgeKind: "current"
                        highlighted: modelData.isDefault
                        actionLabel: qsTr("Use")
                        actionVariant: "tonal"
                        showAction: !modelData.isDefault
                        onActionClicked: soundModel.setDefaultSource(modelData.nodeId)
                    }
                }

                Text {
                    visible: soundModel.available && soundModel.sourceDevices.length === 0
                    width: parent.width
                    text: qsTr("No input devices available")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }
    }
}
