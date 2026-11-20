import QtQuick
import Ryoku.Settings

/*
  Ryoku button system — Primary / Secondary / Tonal / Danger / Ghost.
  Uses Item.enabled (no custom override). Finite color transitions only.
*/
Item {
    id: root
    property string text: ""
    // primary | secondary | tonal | danger | ghost
    property string variant: "tonal"
    signal clicked

    implicitHeight: RyokuTheme.control_height
    implicitWidth: Math.max(96, label.implicitWidth + RyokuTheme.spacing_lg)
    opacity: enabled ? 1.0 : RyokuTheme.disabled_opacity
    scale: pressed ? 0.98 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: RyokuTheme.motion_fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
        }
    }

    readonly property bool hovered: hover.hovered
    readonly property bool pressed: mouse.pressed

    // Base fill per variant; hover/press are a state layer tinted by the label color.
    readonly property color _bg: {
        const v = root.variant
        if (!root.enabled)
            return RyokuTheme.surface_container_high
        if (v === "primary")
            return RyokuTheme.primary
        if (v === "danger")
            return RyokuTheme.error
        if (v === "ghost")
            return "transparent"
        if (v === "secondary")
            return RyokuTheme.surface_container
        // tonal (default)
        return root.hovered ? RyokuTheme.primary_tint : RyokuTheme.surface_container_high
    }

    readonly property color _fg: {
        const v = root.variant
        if (v === "primary")
            return RyokuTheme.on_primary
        if (v === "danger")
            return RyokuTheme.on_error
        if (v === "ghost" || v === "tonal")
            return root.hovered && v === "tonal" ? RyokuTheme.primary : RyokuTheme.on_surface
        return RyokuTheme.on_surface
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: RyokuTheme.radius_sm
        color: root._bg
        border.width: root.variant === "secondary" || root.variant === "ghost" ? RyokuTheme.border_width : 0
        border.color: root.variant === "ghost" ? "transparent" : RyokuTheme.glass_border

        Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }

        RyokuStateLayer {
            anchors.fill: parent
            tint: root._fg
            hovered: root.hovered
            pressed: root.pressed
            disabled: !root.enabled
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: root._fg
            font.pixelSize: RyokuTheme.font_body
            font.bold: root.variant === "primary" || root.variant === "danger"
            Behavior on color { ColorAnimation { duration: RyokuTheme.animation_fast } }
        }
    }

    // Focus ring (keyboard)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: RyokuTheme.radius_sm + 2
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: RyokuTheme.primary
        visible: root.activeFocus
    }

    HoverHandler { id: hover }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus()
            root.clicked()
        }
    }

    Keys.onReturnPressed: if (root.enabled) root.clicked()
    Keys.onEnterPressed: if (root.enabled) root.clicked()
    Keys.onSpacePressed: if (root.enabled) root.clicked()

    activeFocusOnTab: true
}
