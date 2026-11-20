import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ryoku.Settings

Rectangle {
    id: root
    visible: applyController.unsavedDraft
             || applyController.status === "Applied"
             || applyController.status === "NeedsApply"
             || applyController.status === "Ready"
             || applyController.status === "ValidationFailed"
             || applyController.status === "Validating"
             || applyController.status === "AwaitingAuthorization"
             || applyController.status === "Applying"
             || applyController.status === "ApplyFailed"
             || applyController.status === "AuthorizationDenied"
             || applyController.status === "AuthorizationError"
             || applyController.status === "RollingBack"
             || applyController.status === "RollbackFailed"
             || applyController.status === "HashError"
             || applyController.busy
             || (!applyController.helperInstalled && applyController.needsSystemApply)

    color: RyokuTheme.glass_surface
    radius: RyokuTheme.radius_md
    border.width: RyokuTheme.border_width
    border.color: {
        if (applyController.status === "ApplyFailed"
            || applyController.status === "ValidationFailed"
            || applyController.status === "AuthorizationDenied"
            || applyController.status === "AuthorizationError"
            || applyController.status === "RollbackFailed"
            || applyController.status === "HashError"
            || (!applyController.helperInstalled && applyController.needsSystemApply))
            return Qt.rgba(RyokuTheme.error.r, RyokuTheme.error.g, RyokuTheme.error.b, 0.45)
        if (applyController.status === "NeedsApply" || applyController.status === "Ready")
            return Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.40)
        if (applyController.status === "Applied")
            return Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.22)
        return RyokuTheme.glass_border
    }
    implicitHeight: visible ? col.implicitHeight + RyokuTheme.spacing_sm * 2 : 0
    clip: true

    // Top highlight
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: RyokuTheme.radius_sm
        anchors.rightMargin: RyokuTheme.radius_sm
        height: 1
        color: RyokuTheme.glass_highlight
        visible: root.visible
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: RyokuTheme.spacing_md
        anchors.rightMargin: RyokuTheme.spacing_md
        spacing: RyokuTheme.spacing_sm

        Column {
            width: parent.width
            spacing: RyokuTheme.spacing_sm

            RowLayout {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 120
                    spacing: RyokuTheme.spacing_xxs
                    Text {
                        width: parent.width
                        text: applyController.statusText
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: applyController.progressStage.length > 0
                                 || (applyController.lastError.length > 0
                                     && applyController.status !== "Applied")
                                 || (!applyController.helperInstalled && applyController.needsSystemApply)
                        text: {
                            if (applyController.progressStage.length)
                                return applyController.progressStage
                            if (!applyController.helperInstalled && applyController.needsSystemApply)
                                return qsTr("One-time system rebuild required to install the Ryoku Apply helper.")
                            if (applyController.unsavedDraft && applyController.needsSystemApply)
                                return qsTr("Save or reset pending changes before applying.")
                            return applyController.lastError
                        }
                        color: (applyController.lastError.length && !applyController.busy)
                               || !applyController.helperInstalled
                               ? RyokuTheme.error : RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        wrapMode: Text.WordWrap
                    }
                }

                // Discrete static busy marker (no infinite animation / blink)
                Rectangle {
                    visible: applyController.busy
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    Layout.alignment: Qt.AlignVCenter
                    radius: 5
                    color: RyokuTheme.primary
                    opacity: 0.85
                }
            }

            Flow {
                width: parent.width
                spacing: RyokuTheme.spacing_xs
                layoutDirection: Qt.LeftToRight

                RyokuButton {
                    text: qsTr("Details")
                    variant: "ghost"
                    onClicked: detailsPopup.open()
                }
                RyokuButton {
                    text: qsTr("Validate")
                    variant: "secondary"
                    enabled: applyController.canValidate
                    onClicked: applyController.validate()
                }
                RyokuButton {
                    text: qsTr("Apply")
                    variant: "primary"
                    enabled: applyController.canApply
                    onClicked: applyController.apply()
                }
            }
        }
    }

    Popup {
        id: detailsPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(600, Overlay.overlay ? Overlay.overlay.width - 48 : 600)
        height: Math.min(520, Overlay.overlay ? Overlay.overlay.height - 48 : 520)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: RyokuTheme.spacing_lg

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: RyokuTheme.animation_normal }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: RyokuTheme.animation_fast }
        }

        background: Item {
            Rectangle {
                anchors.fill: panel
                anchors.topMargin: RyokuTheme.shadow_y
                radius: RyokuTheme.radius_lg
                color: RyokuTheme.shadow_color
                opacity: 0.55
            }
            Rectangle {
                id: panel
                anchors.fill: parent
                color: RyokuTheme.glass_surface
                radius: RyokuTheme.radius_lg
                border.color: RyokuTheme.glass_border
                border.width: RyokuTheme.border_width
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: RyokuTheme.radius_sm
                    anchors.rightMargin: RyokuTheme.radius_sm
                    height: 1
                    color: RyokuTheme.glass_highlight
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: RyokuTheme.spacing_md
            width: detailsPopup.availableWidth

            Text {
                text: qsTr("Apply details")
                color: RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_section
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Status: %1").arg(applyController.statusText)
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }

            Text {
                visible: applyController.systemPlan.length > 0
                text: qsTr("System")
                color: RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                font.bold: true
            }
            Repeater {
                model: applyController.systemPlan
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: "• " + modelData.label
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_caption
                }
            }

            Text {
                visible: applyController.userPlan.length === 0
                         && applyController.systemPlan.length === 0
                Layout.fillWidth: true
                text: qsTr("No pending apply items.")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: {
                    let lines = []
                    lines.push(qsTr("Validation: %1").arg(
                        applyController.lastValidationSummary.length
                        ? applyController.lastValidationSummary
                        : qsTr("—")))
                    if (applyController.status === "Applied")
                        lines.push(qsTr("Applied state: ✓ Hash verified"))
                    if (applyController.previousGeneration.length)
                        lines.push(qsTr("Previous system: %1").arg(applyController.previousGeneration))
                    if (!applyController.helperInstalled)
                        lines.push(applyController.bootstrapHint)
                    return lines.join("\n")
                }
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: RyokuTheme.glass_surface_high
                radius: RyokuTheme.radius_sm
                border.width: RyokuTheme.border_width
                border.color: RyokuTheme.glass_border

                Flickable {
                    anchors.fill: parent
                    anchors.margins: RyokuTheme.spacing_sm
                    contentHeight: logText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: logText
                        width: parent.width
                        text: applyController.applyLog.length
                              ? applyController.applyLog
                              : qsTr("No output yet.")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_mono
                        font.family: "monospace"
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            Row {
                spacing: RyokuTheme.spacing_sm
                layoutDirection: Qt.LeftToRight
                RyokuButton {
                    text: qsTr("Clear log")
                    variant: "ghost"
                    onClicked: applyController.clearLog()
                }
                RyokuButton {
                    text: qsTr("Rollback")
                    variant: "danger"
                    enabled: applyController.canRollback
                    onClicked: confirmRollback.open()
                }
                Item { width: 8; height: 1 }
                RyokuButton {
                    text: qsTr("Close")
                    variant: "secondary"
                    onClicked: detailsPopup.close()
                }
            }
        }
    }

    RyokuDialog {
        id: confirmRollback
        title: qsTr("Rollback to previous system generation?")
        maxWidth: 420

        Text {
            width: confirmRollback.availableWidth
            wrapMode: Text.WordWrap
            text: qsTr("This requires authentication. Afterwards, settings.json may no longer match the applied generation (Needs Apply).")
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }

        footerComponent: Row {
            spacing: RyokuTheme.spacing_sm
            layoutDirection: Qt.RightToLeft
            width: confirmRollback.availableWidth
            RyokuButton {
                text: qsTr("Rollback")
                variant: "danger"
                onClicked: {
                    confirmRollback.close()
                    applyController.rollback()
                }
            }
            RyokuButton {
                text: qsTr("Cancel")
                variant: "secondary"
                onClicked: confirmRollback.close()
            }
        }
    }
}
