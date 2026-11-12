import QtQuick
import Ryoku.Settings

Item {
    id: root
    property real value: 0.0
    property real from: 0.0
    property real to: 1.0
    // Keyboard increment (arrows); PageUp/PageDown move 10 steps.
    property real stepSize: (to - from) / 100
    // Value bubble shown while dragging / adjusting with the keyboard.
    property bool showValueBubble: true
    property var formatValue: function(v) { return String(Math.round(v)) }
    // Uses Item.enabled — do not redeclare (QML override warning).
    signal moved(real value)

    implicitWidth: 220
    implicitHeight: 28
    opacity: enabled ? 1.0 : RyokuTheme.disabled_opacity
    activeFocusOnTab: true

    // Set on each key press, cleared by the one-shot timer. Not bound to
    // keyHold.running: restart() briefly reports false and would flicker.
    property bool keyAdjusting: false
    readonly property bool bubbleShown: showValueBubble && enabled
                                        && (knobMouse.pressed || keyAdjusting)

    function setFromKeyboard(v) {
        const lo = Math.min(from, to)
        const hi = Math.max(from, to)
        const next = Math.max(lo, Math.min(hi, v))
        keyAdjusting = true
        keyHold.restart()
        if (next === value)
            return
        value = next
        moved(value)
    }

    Keys.onPressed: function(event) {
        if (!root.enabled)
            return
        const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 100
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:
            root.setFromKeyboard(root.value - step)
            break
        case Qt.Key_Right:
        case Qt.Key_Up:
            root.setFromKeyboard(root.value + step)
            break
        case Qt.Key_PageDown:
            root.setFromKeyboard(root.value - step * 10)
            break
        case Qt.Key_PageUp:
            root.setFromKeyboard(root.value + step * 10)
            break
        case Qt.Key_Home:
            root.setFromKeyboard(root.from)
            break
        case Qt.Key_End:
            root.setFromKeyboard(root.to)
            break
        default:
            return
        }
        event.accepted = true
    }

    Timer {
        id: keyHold
        interval: 900
        repeat: false
        onTriggered: root.keyAdjusting = false
    }

    readonly property bool hovered: sliderHover.hovered

    HoverHandler { id: sliderHover }

    // Material 3 track: tonal inactive part, filled active part.
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.24)

        Rectangle {
            width: Math.max(0, knob.x + knob.width / 2)
            height: parent.height
            radius: parent.radius
            color: RyokuTheme.primary
        }
    }

    // Knob geometry is fixed (drag math); only its drawing grows on hover/press.
    Item {
        id: knob
        width: 20
        height: 20
        anchors.verticalCenter: parent.verticalCenter
        x: {
            const span = Math.max(0.0001, root.to - root.from)
            const t = (root.value - root.from) / span
            return Math.max(0, Math.min(1, t)) * (root.width - width)
        }

        // State layer halo
        Rectangle {
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: 20
            color: RyokuTheme.primary
            opacity: !root.enabled ? 0
                   : knobMouse.pressed ? RyokuTheme.state_pressed
                   : root.activeFocus ? RyokuTheme.state_focus
                   : root.hovered ? RyokuTheme.state_hover
                   : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: RyokuTheme.motion_fast } }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: RyokuTheme.primary
            scale: knobMouse.pressed ? 1.15 : (root.hovered || root.activeFocus ? 1.06 : 1.0)
            Behavior on scale {
                NumberAnimation {
                    duration: RyokuTheme.motion_fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
                }
            }
        }

        // Focus ring (keyboard)
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8
            height: parent.height + 8
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: RyokuTheme.primary
            visible: root.activeFocus && !root.hovered && !knobMouse.pressed
        }

        MouseArea {
            id: knobMouse
            anchors.fill: parent
            anchors.margins: -8
            enabled: root.enabled
            cursorShape: Qt.PointingHandCursor
            drag.target: knob
            drag.axis: Drag.XAxis
            drag.minimumX: 0
            drag.maximumX: root.width - knob.width
            onPressed: root.forceActiveFocus()
            onPositionChanged: {
                if (!pressed)
                    return
                const span = root.to - root.from
                const t = knob.x / Math.max(1, root.width - knob.width)
                root.value = root.from + Math.max(0, Math.min(1, t)) * span
                root.moved(root.value)
            }
            onReleased: root.moved(root.value)
        }
    }

    // Value bubble — Material slider value indicator, primary on on_primary.
    Rectangle {
        id: bubble
        readonly property real centerX: knob.x + knob.width / 2
        width: Math.max(36, bubbleLabel.implicitWidth + RyokuTheme.spacing_sm)
        height: 26
        radius: height / 2
        x: Math.max(-RyokuTheme.spacing_xxs,
                    Math.min(root.width - width + RyokuTheme.spacing_xxs, centerX - width / 2))
        y: knob.y - height - 6
        z: 10
        color: RyokuTheme.primary
        opacity: root.bubbleShown ? 1 : 0
        scale: root.bubbleShown ? 1 : 0.85
        visible: opacity > 0
        transformOrigin: Item.Bottom

        Behavior on opacity {
            NumberAnimation {
                duration: root.bubbleShown ? RyokuTheme.motion_fast : RyokuTheme.motion_exit
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: RyokuTheme.motion_fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
            }
        }

        Text {
            id: bubbleLabel
            anchors.centerIn: parent
            text: root.formatValue(root.value)
            color: RyokuTheme.on_primary
            font.pixelSize: RyokuTheme.font_caption
            font.bold: true
        }
    }
}
