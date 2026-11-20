import QtQuick
import Ryoku.Settings

/*
  Material Symbols Rounded icon — single optical box, theme-colored.
  iconName uses Material Symbols ligature/codepoint map (not emoji).
*/
Item {
    id: root

    property string name: ""
    property color color: RyokuTheme.on_surface_muted
    property int size: RyokuTheme.icon_size_nav
    property bool filled: false

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property string glyph: {
        switch (root.name) {
        case "home": return "\ue88a"
        case "palette": return "\ue3b7"
        case "wifi": return "\ue63e"
        case "bluetooth": return "\ue1a7"
        case "volume_up": return "\ue050"
        case "desktop_windows": return "\ue30c"
        case "power_settings_new": return "\ue8ac"
        case "apps": return "\ue5c3"
        case "settings": return "\ue8b8"
        case "system_update_alt": return "\ue8d7"
        case "info": return "\ue88e"
        case "mic": return "\ue029"
        case "battery_saver": return "\uefde"
        case "tune": return "\ue429"
        case "speed": return "\ue9e4"
        case "bolt": return "\uea0b"
        default: return ""
        }
    }

    Text {
        id: glyphText
        anchors.centerIn: parent
        width: root.size
        height: root.size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.glyph
        color: root.color
        font.family: RyokuTheme.icon_font_family
        font.pixelSize: Math.round(root.size * 0.92)
        // Optical centering for Material Symbols PUA glyphs
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.QtRendering
        opacity: root.enabled ? 1.0 : RyokuTheme.disabled_opacity

        Behavior on color {
            ColorAnimation { duration: RyokuTheme.animation_fast }
        }
    }
}
