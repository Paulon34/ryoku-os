// Ryoku overlay — astronaut SystemButtons with a neutral tonal glass surface.
// Based on Keyitdev sddm-astronaut-theme (GPLv3+). Visual polish only.
// Theme colors with alpha are Qt #AARRGGBB.

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

RowLayout {

    spacing: root.font.pointSize

    property var shutdown: ["Shutdown", config.TranslateShutdown || textConstants.shutdown, sddm.canPowerOff]
    property var reboot: ["Reboot", config.TranslateReboot || textConstants.reboot, sddm.canReboot]
    property var suspend: ["Suspend", config.TranslateSuspend || textConstants.suspend, sddm.canSuspend]
    property var hibernate: ["Hibernate", config.TranslateHibernate || textConstants.hibernate, sddm.canHibernate]

    property ComboBox exposedSession

    function themeColor(key, fallback) {
        var v = config[key]
        return v !== undefined && v !== "" ? v : fallback
    }

    Repeater {
        id: systemButtons

        model: [shutdown, reboot, suspend, hibernate]

        RoundButton {
            id: sysBtn
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.topMargin: root.font.pointSize * 6.5

            readonly property color fg: sysBtn.hovered || sysBtn.activeFocus
                                        ? themeColor("HoverSystemButtonsIconsColor", themeColor("SystemButtonsIconsColor", "#e8e8ed"))
                                        : themeColor("SystemButtonsIconsColor", "#e8e8ed")

            text: modelData[1]
            font.pointSize: root.font.pointSize * 0.8
            icon.source: modelData ? Qt.resolvedUrl("../Assets/" + modelData[0] + ".svg") : ""
            icon.height: 2 * Math.round((root.font.pointSize * 3) / 2)
            icon.width: 2 * Math.round((root.font.pointSize * 3) / 2)
            icon.color: sysBtn.fg
            palette.buttonText: sysBtn.fg
            display: AbstractButton.TextUnderIcon
            visible: config.HideSystemButtons != "true" && (config.BypassSystemButtonsChecks == "true" ? 1 : modelData[2])
            hoverEnabled: true

            background: Rectangle {
                anchors.fill: parent
                anchors.margins: -root.font.pointSize * 0.35
                radius: height * 0.28
                color: sysBtn.down
                       ? themeColor("RyokuSystemButtonsPressedBackgroundColor", "#3dffffff")
                       : sysBtn.hovered
                         ? themeColor("RyokuSystemButtonsHoverBackgroundColor", "#2effffff")
                         : themeColor("SystemButtonsBackgroundColor", "#1affffff")
                border.width: sysBtn.activeFocus ? 2 : 1
                border.color: sysBtn.activeFocus
                              ? themeColor("HighlightBorderColor", sysBtn.fg)
                              : themeColor("RyokuSystemButtonsBorderColor", "transparent")

                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Keys.onReturnPressed: clicked()
            onClicked: {
                parent.forceActiveFocus()
                index == 0 ? sddm.powerOff() : index == 1 ? sddm.reboot() : index == 2 ? sddm.suspend() : sddm.hibernate()
            }
            KeyNavigation.left: index > 0 ? parent.children[index-1] : null
        }
    }
}
