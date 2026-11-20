import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

Item {
    id: root
    property string title: qsTr("Page")

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(420, parent.width - RyokuTheme.spacing_xl)
        spacing: RyokuTheme.spacing_sm

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            color: RyokuTheme.on_background
            font.pixelSize: RyokuTheme.font_title
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("Coming in a future Ryoku Settings phase")
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_body
        }
    }
}
