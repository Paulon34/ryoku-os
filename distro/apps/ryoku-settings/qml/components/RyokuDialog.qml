import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ryoku.Settings

/*
  Shared glass dialog shell.
  Children go into the body. Optional footerComponent for action row.
*/
Popup {
    id: root
    property string title: ""
    default property alias dialogContent: bodySlot.data
    property Component footerComponent: null
    property int maxWidth: 560
    property int preferredHeight: -1
    // Override when dialog must not dismiss on outside click (e.g. display preview).
    property int dialogClosePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(maxWidth, Overlay.overlay ? Overlay.overlay.width - 48 : maxWidth)
    height: preferredHeight > 0
            ? preferredHeight
            : Math.min(contentColumn.implicitHeight + padding * 2,
                       Overlay.overlay ? Overlay.overlay.height - 48 : 640)
    modal: true
    focus: true
    closePolicy: dialogClosePolicy
    padding: RyokuTheme.spacing_lg

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: RyokuTheme.animation_normal }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: RyokuTheme.animation_fast }
    }

    background: Item {
        Rectangle {
            anchors.fill: panel
            anchors.topMargin: RyokuTheme.shadow_y
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.shadow_color
            opacity: 0.6
        }
        Rectangle {
            id: panel
            anchors.fill: parent
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: RyokuTheme.radius_sm
                anchors.rightMargin: RyokuTheme.radius_sm
                height: 1
                color: RyokuTheme.glass_highlight
            }
        }
    }

    contentItem: ColumnLayout {
        id: contentColumn
        spacing: RyokuTheme.spacing_md
        width: root.availableWidth

        Text {
            visible: root.title.length > 0
            Layout.fillWidth: true
            text: root.title
            color: RyokuTheme.on_surface
            font.pixelSize: RyokuTheme.font_section
            font.bold: true
        }

        Item {
            id: bodySlot
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
        }

        Loader {
            Layout.fillWidth: true
            active: root.footerComponent !== null
            sourceComponent: root.footerComponent
        }
    }
}
