import QtQuick
import QtQuick.Controls
import Ryoku.Settings

/*
  Sidebar search field. Navigation keys are forwarded through signals so the
  results list can follow the keyboard while focus stays in the field.
*/
TextField {
    id: field

    signal moveSelection(int delta)
    signal submit
    signal escapePressed

    implicitHeight: RyokuTheme.control_height
    leftPadding: RyokuTheme.spacing_sm + 18 + RyokuTheme.spacing_xs
    rightPadding: clearButton.visible ? clearButton.width + RyokuTheme.spacing_xs : RyokuTheme.spacing_sm
    placeholderText: qsTr("Search settings…")
    placeholderTextColor: RyokuTheme.on_surface_muted
    color: RyokuTheme.on_surface
    selectionColor: RyokuTheme.primary_tint_strong
    selectedTextColor: RyokuTheme.on_surface
    font.pixelSize: RyokuTheme.font_body
    Accessible.name: qsTr("Search settings…")

    background: Rectangle {
        radius: RyokuTheme.radius_md
        color: RyokuTheme.glass_surface_high
        border.width: field.activeFocus ? 2 : RyokuTheme.border_width
        border.color: field.activeFocus ? RyokuTheme.primary : RyokuTheme.glass_border
        Behavior on border.color { ColorAnimation { duration: RyokuTheme.motion_fast } }
    }

    // Magnifier drawn from two rectangles (the icon font subset has no search glyph).
    Item {
        anchors.left: parent.left
        anchors.leftMargin: RyokuTheme.spacing_sm
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        opacity: field.activeFocus ? 1 : 0.72

        Rectangle {
            x: 1
            y: 1
            width: 11
            height: 11
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: field.activeFocus ? RyokuTheme.primary : RyokuTheme.on_surface
        }
        Rectangle {
            x: 11
            y: 11
            width: 6
            height: 2
            radius: 1
            rotation: 45
            transformOrigin: Item.Left
            color: field.activeFocus ? RyokuTheme.primary : RyokuTheme.on_surface
        }
    }

    // Shortcut hint as a tooltip: an inline hint collides with the PT-BR
    // placeholder at the sidebar's fixed width.
    ToolTip.visible: hovered && !activeFocus
    ToolTip.delay: 600
    ToolTip.text: "Ctrl+F"

    Item {
        id: clearButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: parent.height
        visible: field.text.length > 0
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Clear search")

        Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: 11
            color: clearHover.hovered ? RyokuTheme.primary_tint : "transparent"
            Text {
                anchors.centerIn: parent
                text: "×"
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_section
            }
        }
        HoverHandler { id: clearHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                field.clear()
                field.forceActiveFocus()
            }
        }
    }

    Keys.onDownPressed: field.moveSelection(1)
    Keys.onUpPressed: field.moveSelection(-1)
    Keys.onReturnPressed: field.submit()
    Keys.onEnterPressed: field.submit()
    Keys.onEscapePressed: field.escapePressed()
}
