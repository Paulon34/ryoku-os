import QtQuick
import Ryoku.Settings

/*
  Compact tonal badge. kind adds meaning beyond color alone (text stays required).
  kind: neutral | applied | needs_apply | current | modified | error
*/
Rectangle {
    id: root
    property string text
    property string kind: "neutral"

    radius: RyokuTheme.radius_pill
    implicitHeight: RyokuTheme.badge_height
    implicitWidth: Math.max(label.implicitWidth + RyokuTheme.spacing_md, 48)

    readonly property color _bg: {
        switch (root.kind) {
        case "applied": return RyokuTheme.primary_tint
        case "needs_apply": return RyokuTheme.primary_tint_strong
        case "current": return RyokuTheme.primary_tint
        case "modified": return Qt.rgba(RyokuTheme.secondary.r, RyokuTheme.secondary.g, RyokuTheme.secondary.b, 0.22)
        case "error": return RyokuTheme.error_tint
        default: return RyokuTheme.surface_container_high
        }
    }

    readonly property color _fg: {
        switch (root.kind) {
        case "applied":
        case "needs_apply":
        case "current": return RyokuTheme.primary
        case "error": return RyokuTheme.error
        case "modified": return RyokuTheme.secondary
        default: return RyokuTheme.on_surface
        }
    }

    color: _bg
    border.width: RyokuTheme.border_width
    border.color: Qt.rgba(_fg.r, _fg.g, _fg.b, 0.28)

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root._fg
        font.pixelSize: RyokuTheme.font_caption
        font.bold: root.kind === "error" || root.kind === "needs_apply"
    }
}
