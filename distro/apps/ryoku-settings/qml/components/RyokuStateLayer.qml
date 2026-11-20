import QtQuick
import Ryoku.Settings

/*
  Material state layer: a tinted overlay whose opacity encodes hover / pressed /
  focus. Put it inside the control's shape (anchors.fill) and drive the flags.
*/
Rectangle {
    id: layer
    property color tint: RyokuTheme.on_surface
    property bool hovered: false
    property bool pressed: false
    property bool focused: false
    property bool disabled: false

    color: tint
    radius: parent && parent.radius !== undefined ? parent.radius : RyokuTheme.radius_sm
    opacity: disabled ? 0
           : pressed ? RyokuTheme.state_pressed
           : focused ? RyokuTheme.state_focus
           : hovered ? RyokuTheme.state_hover
           : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: RyokuTheme.motion_fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
        }
    }
}
