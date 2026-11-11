import QtQuick
import Ryoku.Settings

/*
  Material 3 switch: outlined track + small thumb when off, filled primary
  track + large on_primary thumb (with check) when on. The thumb grows while
  pressed; a 40 px state-layer halo marks hover / press / focus.
*/
Item {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 52
    implicitHeight: 32
    opacity: enabled ? 1.0 : RyokuTheme.disabled_opacity
    activeFocusOnTab: true

    readonly property bool hovered: hover.hovered
    readonly property bool pressed: mouse.pressed
    readonly property real thumbSize: pressed ? 28 : (checked ? 24 : 16)
    readonly property real thumbCenterX: checked ? width - 16 : 16

    function toggle() {
        if (!enabled)
            return
        checked = !checked
        toggled(checked)
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? RyokuTheme.primary : RyokuTheme.surface_container_high
        border.width: root.checked ? 0 : 2
        border.color: Qt.rgba(RyokuTheme.outline.r, RyokuTheme.outline.g, RyokuTheme.outline.b, 0.85)

        Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }
    }

    // State layer halo around the thumb
    Rectangle {
        width: 40
        height: 40
        radius: 20
        x: root.thumbCenterX - width / 2
        y: (root.height - height) / 2
        color: root.checked ? RyokuTheme.primary : RyokuTheme.on_surface
        opacity: !root.enabled ? 0
               : root.pressed ? RyokuTheme.state_pressed
               : root.activeFocus ? RyokuTheme.state_focus
               : root.hovered ? RyokuTheme.state_hover
               : 0
        visible: opacity > 0

        Behavior on x {
            NumberAnimation {
                duration: RyokuTheme.motion_standard
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
            }
        }
        Behavior on opacity { NumberAnimation { duration: RyokuTheme.motion_fast } }
    }

    Rectangle {
        id: thumb
        width: root.thumbSize
        height: width
        radius: width / 2
        x: root.thumbCenterX - width / 2
        y: (root.height - height) / 2
        color: root.checked ? RyokuTheme.on_primary
             : (root.hovered || root.pressed ? RyokuTheme.on_surface : RyokuTheme.outline)

        Behavior on x {
            NumberAnimation {
                duration: RyokuTheme.motion_standard
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: RyokuTheme.motion_fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
            }
        }
        Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }

        Text {
            anchors.centerIn: parent
            text: "✓"
            color: RyokuTheme.primary
            font.pixelSize: 13
            font.bold: true
            opacity: root.checked && thumb.width >= 22 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: RyokuTheme.motion_fast } }
        }
    }

    // Focus ring (keyboard)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: RyokuTheme.primary
        visible: root.activeFocus && !hover.hovered
    }

    HoverHandler { id: hover }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus()
            root.toggle()
        }
    }

    Keys.onSpacePressed: root.toggle()
    Keys.onReturnPressed: root.toggle()
    Keys.onEnterPressed: root.toggle()
}
