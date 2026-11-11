import QtQuick
import Ryoku.Settings

/*
  Sidebar nav item — Material 3 navigation drawer item. The selected pill is a
  single indicator owned by the sidebar (Main.qml) that slides between items;
  the item itself draws the state layer, label and icon.
*/
Item {
    id: root
    property string title
    property string iconName: ""
    // Legacy alias — prefer iconName.
    property alias glyph: root.iconName
    property bool selected: false
    signal clicked

    implicitHeight: RyokuTheme.nav_item_height
    implicitWidth: 200
    activeFocusOnTab: true

    Item {
        id: pill
        anchors.fill: parent
        property real radius: RyokuTheme.radius_md

        RyokuStateLayer {
            anchors.fill: parent
            radius: pill.radius
            tint: root.selected ? RyokuTheme.primary : RyokuTheme.on_surface
            hovered: hover.hovered
            pressed: mouse.pressed
        }

        // Focus ring (keyboard)
        Rectangle {
            anchors.fill: parent
            radius: pill.radius
            color: "transparent"
            border.width: 2
            border.color: RyokuTheme.primary
            visible: root.activeFocus
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: RyokuTheme.spacing_sm + RyokuTheme.spacing_xxs
            anchors.rightMargin: RyokuTheme.spacing_sm
            spacing: RyokuTheme.spacing_sm

            Item {
                width: RyokuTheme.icon_size_nav
                height: parent.height
                RyokuIcon {
                    anchors.centerIn: parent
                    name: root.iconName
                    size: RyokuTheme.icon_size_nav
                    color: root.selected ? RyokuTheme.primary
                         : (hover.hovered || root.activeFocus ? RyokuTheme.on_surface
                                                              : RyokuTheme.on_surface_muted)
                    Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: root.selected ? RyokuTheme.primary : RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                width: parent.width - RyokuTheme.icon_size_nav - parent.spacing
                Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }
            }
        }
    }

    HoverHandler { id: hover }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus()
            root.clicked()
        }
    }

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
