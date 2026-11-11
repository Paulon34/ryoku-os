import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

/*
  Shared device / network / audio row — glass + optional leading / badge / action.
*/
Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property string leading: ""
    // Prefer Material Symbols via RyokuIcon when set (over legacy leading text).
    property string leadingIcon: ""
    property string badgeText: ""
    property string badgeKind: "neutral"
    property bool highlighted: false
    property bool showAction: true
    property string actionLabel: qsTr("Connect")
    property string actionVariant: "tonal"
    signal actionClicked()
    signal clicked()

    radius: RyokuTheme.radius_md
    color: highlighted ? RyokuTheme.primary_tint_strong : RyokuTheme.glass_surface_high
    border.width: RyokuTheme.border_width
    border.color: highlighted
                  ? Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.35)
                  : RyokuTheme.glass_border
    implicitHeight: Math.max(48, row.implicitHeight + RyokuTheme.spacing_sm)
    implicitWidth: 200

    Behavior on color { ColorAnimation { duration: RyokuTheme.animation_fast } }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: RyokuTheme.spacing_sm
        anchors.rightMargin: RyokuTheme.spacing_sm
        spacing: RyokuTheme.spacing_sm

        Item {
            visible: root.leadingIcon.length > 0 || root.leading.length > 0
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter

            RyokuIcon {
                anchors.centerIn: parent
                visible: root.leadingIcon.length > 0
                name: root.leadingIcon
                size: RyokuTheme.icon_size_nav
                color: root.highlighted ? RyokuTheme.primary : RyokuTheme.on_surface_muted
            }

            Text {
                anchors.centerIn: parent
                visible: root.leadingIcon.length === 0 && root.leading.length > 0
                text: root.leading
                color: root.highlighted ? RyokuTheme.primary : RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_section
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: RyokuTheme.spacing_xxs
            Text {
                width: parent.width
                text: root.title
                color: RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                font.bold: root.highlighted
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
                elide: Text.ElideRight
            }
        }

        RyokuBadge {
            Layout.alignment: Qt.AlignVCenter
            visible: root.badgeText.length > 0
            text: root.badgeText
            kind: root.badgeKind
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailing.length > 0 && root.badgeText.length === 0
            text: root.trailing
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }

        RyokuButton {
            Layout.alignment: Qt.AlignVCenter
            visible: root.showAction
            text: root.actionLabel
            variant: root.actionVariant
            onClicked: root.actionClicked()
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
