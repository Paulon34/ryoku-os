import QtQuick
import QtQuick.Controls
import Ryoku.Settings

Item {
    id: root
    property var model: []
    property int currentIndex: 0
    // Uses Item.enabled — do not redeclare (QML override warning).
    signal activated(int index)

    implicitHeight: RyokuTheme.control_height
    implicitWidth: Math.max(180, label.implicitWidth + 48)
    opacity: enabled ? 1.0 : RyokuTheme.disabled_opacity

    readonly property string currentText: {
        if (!model || currentIndex < 0 || currentIndex >= model.length)
            return qsTr("—")
        const item = model[currentIndex]
        if (typeof item === "string")
            return item
        if (item && item.label !== undefined)
            return item.label
        return String(item)
    }

    Rectangle {
        anchors.fill: parent
        radius: RyokuTheme.radius_sm
        color: hover.hovered ? RyokuTheme.surface_container_high : RyokuTheme.surface_container

        Row {
            anchors.fill: parent
            anchors.leftMargin: RyokuTheme.spacing_md
            anchors.rightMargin: RyokuTheme.spacing_md
            spacing: RyokuTheme.spacing_sm

            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - chevron.implicitWidth - parent.spacing
                text: root.currentText
                color: RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                elide: Text.ElideRight
            }

            Text {
                id: chevron
                anchors.verticalCenter: parent.verticalCenter
                text: "▾"
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.open()
    }

    Popup {
        id: popup
        y: root.height + 4
        width: Math.max(root.width, 220)
        padding: 4
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            color: RyokuTheme.glass_surface_high
            radius: RyokuTheme.radius_md
            border.color: RyokuTheme.glass_border
            border.width: RyokuTheme.border_width
        }

        contentItem: ListView {
            id: list
            clip: true
            implicitHeight: Math.min(contentHeight, 240)
            model: root.model
            delegate: Item {
                required property int index
                required property var modelData
                width: list.width
                height: 34

                readonly property string labelText: {
                    if (typeof modelData === "string")
                        return modelData
                    if (modelData && modelData.label !== undefined)
                        return modelData.label
                    return String(modelData)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: RyokuTheme.radius_sm
                    color: index === root.currentIndex
                           ? RyokuTheme.primary_tint_strong
                           : (rowHover.hovered ? RyokuTheme.primary_tint : "transparent")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: RyokuTheme.spacing_sm
                    anchors.right: parent.right
                    anchors.rightMargin: RyokuTheme.spacing_sm
                    text: labelText
                    color: index === root.currentIndex ? RyokuTheme.primary : RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_caption
                    elide: Text.ElideRight
                }

                HoverHandler { id: rowHover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentIndex = index
                        root.activated(index)
                        popup.close()
                    }
                }
            }
        }
    }
}
