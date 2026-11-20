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

    Component.onCompleted: {
        bluetoothModel.setPageActive(true)
        bluetoothModel.refresh()
    }
    Component.onDestruction: bluetoothModel.setPageActive(false)

    Connections {
        target: bluetoothModel
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
                    text: qsTr("Bluetooth")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                    Layout.fillWidth: true
                }
                RyokuBadge {
                    text: !bluetoothModel.available ? qsTr("Unavailable")
                          : (bluetoothModel.powered ? qsTr("On") : qsTr("Off"))
                    kind: !bluetoothModel.available ? "error"
                          : (bluetoothModel.powered ? "applied" : "neutral")
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Connect and manage nearby devices")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !bluetoothModel.available || bluetoothModel.error.length > 0
            wrapMode: Text.WordWrap
            text: bluetoothModel.error.length ? bluetoothModel.error : qsTr("BlueZ unavailable")
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

        // ── Adapter ───────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Adapter")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                RowLayout {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    Column {
                        Layout.fillWidth: true
                        spacing: RyokuTheme.spacing_xxs
                        Text {
                            width: parent.width
                            text: bluetoothModel.adapterName.length
                                  ? bluetoothModel.adapterName
                                  : qsTr("Bluetooth radio")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: bluetoothModel.discovering
                                  ? qsTr("Scanning for nearby devices…")
                                  : qsTr("Turn on to connect headphones, speakers, and more.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                    RyokuToggle {
                        checked: bluetoothModel.powered
                        enabled: bluetoothModel.available
                        onToggled: function(v) { bluetoothModel.setPowered(v) }
                    }
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: bluetoothModel.discovering ? qsTr("Stop scan") : qsTr("Scan")
                        variant: bluetoothModel.discovering ? "secondary" : "tonal"
                        enabled: bluetoothModel.powered
                        onClicked: {
                            root.statusMessage = ""
                            if (bluetoothModel.discovering)
                                bluetoothModel.stopDiscovery()
                            else
                                bluetoothModel.startDiscovery()
                        }
                    }
                    RyokuButton {
                        text: qsTr("Refresh")
                        variant: "ghost"
                        onClicked: bluetoothModel.refresh()
                    }
                    RyokuBadge {
                        visible: bluetoothModel.discovering
                        text: qsTr("Scanning")
                        kind: "current"
                    }
                }
            }
        }

        // ── Connected ─────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Connected")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    model: bluetoothModel
                    delegate: RyokuDeviceRow {
                        required property string name
                        required property string address
                        required property string path
                        required property bool connected
                        required property string statusLabel
                        width: parent.width
                        height: connected ? implicitHeight : 0
                        visible: connected
                        leading: "⬡"
                        title: name.length ? name : address
                        subtitle: qsTr("Connected")
                        badgeText: qsTr("Connected")
                        badgeKind: "applied"
                        highlighted: true
                        actionLabel: qsTr("Disconnect")
                        actionVariant: "secondary"
                        onActionClicked: bluetoothModel.disconnectDevice(path)
                    }
                }

                Text {
                    visible: bluetoothModel.connectedCount === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("No connected devices")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        // ── My devices (paired, not connected) ────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("My devices")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    id: pairedRepeater
                    model: bluetoothModel
                    delegate: RyokuDeviceRow {
                        required property string name
                        required property string address
                        required property string path
                        required property bool connected
                        required property bool paired
                        required property string statusLabel
                        width: parent.width
                        height: (!connected && paired) ? implicitHeight : 0
                        visible: !connected && paired
                        leading: "⬡"
                        title: name.length ? name : address
                        subtitle: qsTr("Paired")
                        badgeText: qsTr("Paired")
                        badgeKind: "current"
                        actionLabel: qsTr("Connect")
                        actionVariant: "tonal"
                        onActionClicked: {
                            root.statusMessage = ""
                            bluetoothModel.connectDevice(path)
                        }
                    }
                }

                Text {
                    visible: bluetoothModel.powered && bluetoothModel.count === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("No paired devices yet")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        // ── Nearby ────────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Nearby")
            visible: bluetoothModel.powered

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    model: bluetoothModel
                    delegate: RyokuDeviceRow {
                        required property string name
                        required property string address
                        required property string path
                        required property bool connected
                        required property bool paired
                        required property string statusLabel
                        width: parent.width
                        height: (!connected && !paired) ? implicitHeight : 0
                        visible: !connected && !paired
                        leading: "⬡"
                        title: name.length ? name : address
                        subtitle: qsTr("Available")
                        badgeText: qsTr("Available")
                        badgeKind: "neutral"
                        actionLabel: qsTr("Pair")
                        actionVariant: "tonal"
                        onActionClicked: {
                            root.statusMessage = ""
                            bluetoothModel.pairDevice(path)
                        }
                    }
                }

                Text {
                    visible: bluetoothModel.count === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: bluetoothModel.discovering
                          ? qsTr("Looking for nearby devices…")
                          : qsTr("No nearby devices — try Scan")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                Text {
                    visible: bluetoothModel.count > 0 && bluetoothModel.discovering
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Scanning…")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }
    }
}
