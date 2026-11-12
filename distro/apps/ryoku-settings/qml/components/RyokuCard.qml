import QtQuick
import Ryoku.Settings

/*
  Shared Ryoku card — tonal surface on the base plane, tonal border, two-step
  elevation (ambient + key, no blur), section title in primary.
  `interactive` adds a hover state for cards that are themselves clickable.
*/
Item {
    id: root
    default property alias content: body.data
    property alias title: titleLabel.text
    property bool showTitle: titleLabel.text.length > 0
    property bool interactive: false
    readonly property bool hovered: hover.hovered

    implicitHeight: column.implicitHeight + RyokuTheme.spacing_md * 2 + RyokuTheme.elevation_key_y
    implicitWidth: 200

    HoverHandler {
        id: hover
        enabled: root.interactive
    }

    // Key shadow (directional) — omitted in the Economy profile.
    Rectangle {
        anchors.fill: panel
        anchors.topMargin: RyokuTheme.elevation_key_y + (root.interactive && root.hovered ? 1 : 0)
        anchors.leftMargin: RyokuTheme.spacing_xxs
        anchors.rightMargin: RyokuTheme.spacing_xxs
        radius: RyokuTheme.radius_lg
        color: Qt.rgba(0, 0, 0, 1)
        opacity: RyokuTheme.elevation_key
        visible: opacity > 0
    }

    // Ambient shadow — a 1 px dark rim under the surface.
    Rectangle {
        anchors.fill: panel
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: RyokuTheme.radius_lg
        color: Qt.rgba(0, 0, 0, 1)
        opacity: RyokuTheme.elevation_ambient
    }

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: column.implicitHeight + RyokuTheme.spacing_md * 2
        radius: RyokuTheme.radius_lg
        color: RyokuTheme.card_surface
        border.width: RyokuTheme.border_width
        border.color: root.interactive && root.hovered ? RyokuTheme.card_border_hover : RyokuTheme.card_border

        Behavior on border.color {
            ColorAnimation { duration: RyokuTheme.motion_fast }
        }

        RyokuStateLayer {
            anchors.fill: parent
            tint: RyokuTheme.primary
            hovered: root.interactive && root.hovered
        }

        // Top edge highlight (light catching the surface edge)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: RyokuTheme.radius_lg
            anchors.rightMargin: RyokuTheme.radius_lg
            height: 1
            color: RyokuTheme.glass_highlight
        }

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: RyokuTheme.spacing_md
            spacing: RyokuTheme.spacing_sm

            Text {
                id: titleLabel
                visible: root.showTitle
                width: parent.width
                color: RyokuTheme.primary
                font.pixelSize: RyokuTheme.font_card
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
            }

            Item {
                id: body
                width: parent.width
                height: childrenRect.height
            }
        }
    }
}
