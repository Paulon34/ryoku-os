import QtQuick
import Ryoku.Settings

/*
  Plain Text — not Controls.Label.
  Color from RyokuTheme.on_surface (snake_case — avoids QML on* signal-handler clash).
*/
Text {
    color: RyokuTheme.on_surface
    font.pixelSize: RyokuTheme.font_body
}
