import QtQuick
import Ryoku.Settings

Item {
    id: root
    property string label
    property string value
    property string hint: ""

    implicitHeight: col.implicitHeight
    width: parent ? parent.width : 400

    Column {
        id: col
        width: parent.width
        spacing: RyokuTheme.spacing_xxs

        Text {
            width: parent.width
            text: root.label
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }

        Text {
            width: parent.width
            text: root.value
            color: RyokuTheme.on_surface
            font.pixelSize: RyokuTheme.font_body
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            visible: root.hint.length > 0
            text: root.hint
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
            wrapMode: Text.WordWrap
        }
    }
}
