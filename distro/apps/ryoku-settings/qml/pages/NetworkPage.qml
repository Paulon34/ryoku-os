import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    property string pendingSsid: ""
    property string statusMessage: ""

    function signalLabel(strength) {
        if (strength >= 80)
            return qsTr("Excellent")
        if (strength >= 55)
            return qsTr("Good")
        if (strength >= 30)
            return qsTr("Fair")
        return qsTr("Weak")
    }

    function signalGlyph(strength) {
        if (strength >= 80)
            return "▂▄▆█"
        if (strength >= 55)
            return "▂▄▆ "
        if (strength >= 30)
            return "▂▄  "
        return "▂   "
    }

    Component.onCompleted: {
        networkModel.refresh()
        networkModel.requestScan()
    }

    Connections {
        target: networkModel
        function onOperationFailed(message) {
            root.statusMessage = message
        }
        function onPasswordRequired(ssid) {
            root.pendingSsid = ssid
            passwordField.text = ""
            passwordDialog.open()
        }
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
                    text: qsTr("Network")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                    Layout.fillWidth: true
                }
                RyokuBadge {
                    text: networkModel.wifiEnabled ? qsTr("Wi-Fi On") : qsTr("Wi-Fi Off")
                    kind: networkModel.wifiEnabled ? "applied" : "neutral"
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Wi-Fi and network connections")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !networkModel.available || networkModel.error.length > 0
            wrapMode: Text.WordWrap
            text: networkModel.error.length ? networkModel.error : qsTr("NetworkManager unavailable")
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

        // ── Wi-Fi control ─────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Wi-Fi")

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
                            text: qsTr("Wireless radio")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: networkModel.wifiHardwareAvailable
                                  ? (networkModel.primaryDevice.length
                                     ? qsTr("Adapter · %1").arg(networkModel.primaryDevice)
                                     : qsTr("Hardware available"))
                                  : qsTr("No Wi-Fi hardware detected")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                    RyokuToggle {
                        checked: networkModel.wifiEnabled
                        enabled: networkModel.available && networkModel.wifiHardwareAvailable
                        onToggled: function(v) { networkModel.setWifiEnabled(v) }
                    }
                }

                Text {
                    width: parent.width
                    visible: networkModel.ethernetLabel.length > 0
                             && networkModel.ethernetLabel !== "—"
                             && networkModel.ethernetLabel.toLowerCase().indexOf("unavailable") < 0
                    wrapMode: Text.WordWrap
                    text: qsTr("Ethernet · %1").arg(networkModel.ethernetLabel)
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                RyokuButton {
                    text: qsTr("Scan networks")
                    variant: "secondary"
                    enabled: networkModel.available && networkModel.wifiEnabled
                    onClicked: {
                        root.statusMessage = ""
                        networkModel.refresh()
                        networkModel.requestScan()
                    }
                }
            }
        }

        // ── Current connection ────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Connected")
            visible: networkModel.connectedSsid.length > 0

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                RowLayout {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm

                    Text {
                        text: root.signalGlyph(networkModel.connectedStrength)
                        color: RyokuTheme.primary
                        font.pixelSize: RyokuTheme.font_section
                        font.family: "monospace"
                        Layout.preferredWidth: 48
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: RyokuTheme.spacing_xxs
                        Text {
                            width: parent.width
                            text: networkModel.connectedSsid
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_section
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: qsTr("Wi-Fi · %1").arg(root.signalLabel(networkModel.connectedStrength))
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }

                    RyokuBadge {
                        text: qsTr("Connected")
                        kind: "applied"
                    }
                }

                RyokuButton {
                    text: qsTr("Disconnect")
                    variant: "secondary"
                    onClicked: networkModel.disconnectWifi()
                }
            }
        }

        // ── Available networks ────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Available networks")
            visible: networkModel.wifiEnabled || !networkModel.wifiHardwareAvailable

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    model: networkModel
                    delegate: RyokuDeviceRow {
                        required property string ssid
                        required property int strength
                        required property bool secured
                        required property string securityLabel
                        required property bool connected
                        width: parent.width
                        height: connected ? 0 : implicitHeight
                        visible: !connected
                        leading: root.signalGlyph(strength)
                        title: ssid
                        subtitle: qsTr("%1 · %2").arg(root.signalLabel(strength)).arg(securityLabel)
                        badgeText: secured ? qsTr("Secured") : qsTr("Open")
                        badgeKind: secured ? "neutral" : "modified"
                        actionLabel: qsTr("Connect")
                        actionVariant: "tonal"
                        onActionClicked: {
                            root.statusMessage = ""
                            networkModel.connectToNetwork(ssid)
                        }
                    }
                }

                Text {
                    visible: !networkModel.wifiEnabled || networkModel.count === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !networkModel.wifiEnabled
                          ? qsTr("Turn on Wi-Fi to see nearby networks.")
                          : qsTr("No Wi-Fi networks found")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }
    }

    RyokuDialog {
        id: passwordDialog
        title: qsTr("Connect to %1").arg(root.pendingSsid)
        maxWidth: 420

        Column {
            width: passwordDialog.availableWidth
            spacing: RyokuTheme.spacing_sm
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Password")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }
            TextField {
                id: passwordField
                width: parent.width
                echoMode: TextInput.Password
                color: RyokuTheme.on_surface
                placeholderText: qsTr("Enter Wi-Fi password")
                Keys.onReturnPressed: connectBtn.clicked()
                background: Rectangle {
                    color: RyokuTheme.glass_surface_high
                    radius: RyokuTheme.radius_sm
                    border.color: RyokuTheme.glass_border
                    border.width: RyokuTheme.border_width
                }
            }
        }

        footerComponent: Row {
            spacing: RyokuTheme.spacing_sm
            layoutDirection: Qt.RightToLeft
            width: passwordDialog.availableWidth
            RyokuButton {
                id: connectBtn
                text: qsTr("Connect")
                variant: "primary"
                onClicked: {
                    const ssid = root.pendingSsid
                    const pw = passwordField.text
                    passwordField.text = ""
                    passwordDialog.close()
                    networkModel.connectToNetwork(ssid, pw)
                }
            }
            RyokuButton {
                text: qsTr("Cancel")
                variant: "secondary"
                onClicked: {
                    passwordField.text = ""
                    passwordDialog.close()
                }
            }
        }
    }
}
