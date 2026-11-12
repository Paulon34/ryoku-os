import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    property bool dirty: false
    property bool justSaved: false
    property bool needsApply: false
    property string errorMessage: ""
    property string runtimeNote: ""
    property string relativeTarget: ""

    readonly property string statusLabel: {
        if (errorMessage.length > 0)
            return qsTr("Error")
        if (displayModel.previewActive)
            return qsTr("Previewing")
        if (justSaved && needsApply)
            return qsTr("Needs Apply")
        if (justSaved)
            return qsTr("Saved")
        if (dirty || displayModel.draftDirty)
            return qsTr("Modified")
        return qsTr("Current")
    }

    readonly property string statusKind: {
        if (errorMessage.length > 0)
            return "error"
        if (displayModel.previewActive)
            return "current"
        if (justSaved && needsApply)
            return "needs_apply"
        if (justSaved)
            return "applied"
        if (dirty || displayModel.draftDirty)
            return "modified"
        return "neutral"
    }

    readonly property var selectedDraft: displayModel.selectedDraft || ({})
    readonly property var others: displayModel.otherEnabledMonitorNames()
    readonly property bool wide: width >= 720

    function markDirty() {
        dirty = true
        justSaved = false
        needsApply = false
        errorMessage = ""
    }

    function saveToRyoku() {
        errorMessage = ""
        const monitors = displayModel.draftMonitorsForSave()
        if (!settingsStore.saveDisplayMonitors(monitors)) {
            errorMessage = settingsStore.lastWriteError.length
                           ? settingsStore.lastWriteError
                           : qsTr("Save failed")
            return
        }
        dirty = false
        justSaved = true
        // display.monitors is persisted but not projected to hyprland.nix yet (7G-A).
        needsApply = false
        runtimeNote = qsTr("Saved to Ryoku — Hyprland projection comes later.")
        gitStatus.refresh()
    }

    function syncRelativeTarget() {
        const list = displayModel.otherEnabledMonitorNames()
        if (list.indexOf(relativeTarget) >= 0)
            return
        relativeTarget = list.length ? list[0] : ""
    }

    function formatRefresh(hz) {
        const n = Number(hz)
        if (!isFinite(n) || n <= 0)
            return "—"
        const rounded = Math.round(n)
        if (Math.abs(n - rounded) < 0.05)
            return qsTr("%1 Hz").arg(rounded)
        return qsTr("%1 Hz").arg(n.toFixed(2))
    }

    function formatModeSummary(w, h, hz) {
        if (!w || !h)
            return "—"
        return qsTr("%1 × %2 · %3").arg(w).arg(h).arg(formatRefresh(hz))
    }

    function monitorTitle(name, description) {
        if (description && description.length)
            return description
        return name
    }

    Component.onCompleted: {
        displayModel.refresh()
        syncRelativeTarget()
    }

    Connections {
        target: displayModel
        function onChanged() {
            if (displayModel.draftDirty)
                root.markDirty()
            root.syncRelativeTarget()
        }
        function onOperationFailed(message) {
            root.errorMessage = message
        }
        function onPreviewStarted() {
            confirmDialog.open()
        }
        function onPreviewEnded(kept) {
            confirmDialog.close()
            if (kept)
                root.runtimeNote = qsTr("Runtime applied")
        }
    }

    Connections {
        target: settingsStore
        function onExternalChangePendingChanged() {
            if (!settingsStore.externalChangePending)
                return
            if (!root.dirty && !displayModel.draftDirty && !displayModel.previewActive)
                settingsStore.acknowledgeExternalChange()
        }
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: RyokuTheme.spacing_md

        // ── Header ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: RyokuTheme.spacing_xxs

            RowLayout {
                Layout.fillWidth: true
                spacing: RyokuTheme.spacing_sm
                Text {
                    text: qsTr("Displays")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                    Layout.fillWidth: true
                }
                RyokuBadge {
                    text: displayModel.available
                          ? (displayModel.count === 1
                             ? qsTr("1 connected")
                             : qsTr("%1 connected").arg(displayModel.count))
                          : qsTr("Unavailable")
                    kind: displayModel.available ? "current" : "error"
                }
                RyokuBadge {
                    text: root.statusLabel
                    kind: root.statusKind
                }
                RyokuButton {
                    text: qsTr("Refresh")
                    variant: "ghost"
                    enabled: !displayModel.previewActive
                    onClicked: displayModel.refresh()
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Configure monitors, resolution and layout")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !displayModel.available || displayModel.error.length > 0
            wrapMode: Text.WordWrap
            text: displayModel.error.length ? displayModel.error : qsTr("Hyprland displays unavailable")
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }
        Text {
            Layout.fillWidth: true
            visible: root.errorMessage.length > 0
            wrapMode: Text.WordWrap
            text: root.errorMessage
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }
        Text {
            Layout.fillWidth: true
            visible: root.runtimeNote.length > 0 || displayModel.statusMessage.length > 0
            wrapMode: Text.WordWrap
            text: root.runtimeNote.length ? root.runtimeNote : displayModel.statusMessage
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }
        Text {
            Layout.fillWidth: true
            visible: settingsStore.externalChangePending && (root.dirty || displayModel.draftDirty)
            wrapMode: Text.WordWrap
            text: qsTr("Configuration changed externally.")
            color: RyokuTheme.error
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── Recovery ──────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            visible: displayModel.unfinishedPreviewAvailable
            title: qsTr("Recovery")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("An unfinished display preview was detected.")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_body
                }
                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Restore previous layout")
                        variant: "primary"
                        onClicked: displayModel.restoreUnfinishedPreview()
                    }
                    RyokuButton {
                        text: qsTr("Dismiss")
                        variant: "ghost"
                        onClicked: displayModel.dismissUnfinishedPreview()
                    }
                }
            }
        }

        // ── Layout preview (existing data) ────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Layout")

            Item {
                id: canvas
                width: parent.width
                height: root.wide ? 180 : 150

                readonly property var items: displayModel.layoutPreview
                readonly property var bounds: {
                    let maxX = 1, maxY = 1
                    for (let i = 0; i < items.length; ++i) {
                        const m = items[i]
                        maxX = Math.max(maxX, (m.x || 0) + (m.width || 1))
                        maxY = Math.max(maxY, (m.y || 0) + (m.height || 1))
                    }
                    return { maxX: maxX, maxY: maxY }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: RyokuTheme.radius_md
                    color: RyokuTheme.glass_surface_high
                    border.width: RyokuTheme.border_width
                    border.color: RyokuTheme.glass_border
                }

                Text {
                    anchors.centerIn: parent
                    visible: canvas.items.length === 0
                    text: qsTr("No enabled displays")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Repeater {
                    model: canvas.items
                    delegate: Rectangle {
                        required property var modelData
                        readonly property real sx: (parent.width - 24) / Math.max(1, canvas.bounds.maxX)
                        readonly property real sy: (parent.height - 24) / Math.max(1, canvas.bounds.maxY)
                        readonly property real s: Math.min(sx, sy)
                        readonly property bool selected: modelData.name === displayModel.selectedName
                        x: 12 + (modelData.x || 0) * s
                        y: 12 + (modelData.y || 0) * s
                        width: Math.max(56, (modelData.width || 100) * s)
                        height: Math.max(36, (modelData.height || 60) * s)
                        radius: RyokuTheme.radius_sm
                        color: selected ? RyokuTheme.primary_tint_strong : RyokuTheme.glass_surface
                        border.width: selected || modelData.focused ? 2 : RyokuTheme.border_width
                        border.color: selected ? RyokuTheme.primary
                                     : (modelData.focused ? RyokuTheme.outline : RyokuTheme.glass_border)

                        Behavior on color { ColorAnimation { duration: RyokuTheme.animation_fast } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            width: parent.width - 8
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name || ""
                                color: selected ? RyokuTheme.primary : RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_caption
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: (modelData.width || 0) + " × " + (modelData.height || 0)
                                color: selected ? RyokuTheme.primary : RyokuTheme.on_surface_muted
                                font.pixelSize: RyokuTheme.font_caption
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: displayModel.selectedName = modelData.name
                        }
                    }
                }
            }
        }

        // ── Monitor list ──────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Monitors")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    model: displayModel
                    delegate: RyokuDeviceRow {
                        required property string name
                        required property string description
                        required property string modeLabel
                        required property bool focused
                        required property bool displayEnabled
                        width: parent.width
                        leading: "▣"
                        title: root.monitorTitle(name, description)
                        subtitle: {
                            let parts = []
                            if (description.length && description !== name)
                                parts.push(name)
                            parts.push(modeLabel)
                            return parts.join(" · ")
                        }
                        badgeText: !displayEnabled ? qsTr("Disabled")
                                 : (focused ? qsTr("Focused")
                                    : (name === displayModel.selectedName ? qsTr("Selected") : qsTr("Enabled")))
                        badgeKind: !displayEnabled ? "neutral"
                                 : (focused || name === displayModel.selectedName ? "current" : "applied")
                        highlighted: name === displayModel.selectedName
                        actionLabel: qsTr("Select")
                        actionVariant: "tonal"
                        showAction: name !== displayModel.selectedName
                        onActionClicked: displayModel.selectedName = name
                        onClicked: displayModel.selectedName = name
                    }
                }

                Text {
                    visible: displayModel.count === 0
                    width: parent.width
                    text: qsTr("No monitors detected")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        // ── Selected monitor controls ─────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            visible: !!(selectedDraft.name)
            title: selectedDraft.name || qsTr("Selected display")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                RowLayout {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    Column {
                        Layout.fillWidth: true
                        spacing: RyokuTheme.spacing_xxs
                        Text {
                            width: parent.width
                            text: root.formatModeSummary(selectedDraft.width, selectedDraft.height, selectedDraft.refreshRate)
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_section
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: settingsStore.hasDisplayMonitors
                                  ? qsTr("Ryoku has a saved layout — runtime draft below")
                                  : qsTr("Editing runtime draft")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                    RyokuBadge {
                        text: selectedDraft.enabled === false ? qsTr("Disabled") : qsTr("Enabled")
                        kind: selectedDraft.enabled === false ? "neutral" : "applied"
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    Text {
                        text: qsTr("Resolution / Refresh")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                    }
                    RyokuComboBox {
                        width: parent.width
                        enabled: !displayModel.previewActive && selectedDraft.enabled !== false
                        model: displayModel.selectedModeLabels
                        currentIndex: Math.max(0, displayModel.selectedModeIndex)
                        onActivated: function(index) {
                            displayModel.setDraftModeIndex(index)
                            root.markDirty()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Scale")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            text: Math.round((selectedDraft.scale || 1) * 100) + "%"
                            color: RyokuTheme.primary
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                    }
                    RyokuSlider {
                        width: parent.width
                        from: 0.5
                        to: 3.0
                        value: selectedDraft.scale || 1.0
                        enabled: !displayModel.previewActive && selectedDraft.enabled !== false
                        stepSize: 0.05
                        formatValue: function(v) { return Math.round(Math.round(v * 20) / 20 * 100) + "%" }
                        onMoved: function(v) {
                            displayModel.setDraftScale(Math.round(v * 20) / 20)
                            root.markDirty()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    Text {
                        text: qsTr("Position")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                    }
                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("X")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                            Layout.preferredWidth: 16
                        }
                        SpinBox {
                            from: -7680
                            to: 7680
                            value: selectedDraft.x || 0
                            enabled: !displayModel.previewActive && selectedDraft.enabled !== false
                            editable: true
                            onValueModified: {
                                displayModel.setDraftX(value)
                                root.markDirty()
                            }
                            Layout.fillWidth: true
                        }
                        Text {
                            text: qsTr("Y")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                            Layout.preferredWidth: 16
                        }
                        SpinBox {
                            from: -4320
                            to: 4320
                            value: selectedDraft.y || 0
                            enabled: !displayModel.previewActive && selectedDraft.enabled !== false
                            editable: true
                            onValueModified: {
                                displayModel.setDraftY(value)
                                root.markDirty()
                            }
                            Layout.fillWidth: true
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    visible: root.others.length > 0

                    Text {
                        text: qsTr("Place relative to")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                    }
                    RyokuComboBox {
                        width: parent.width
                        model: root.others
                        currentIndex: Math.max(0, root.others.indexOf(root.relativeTarget))
                        onActivated: function(index) {
                            root.relativeTarget = root.others[index] || ""
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: RyokuTheme.spacing_sm
                        Repeater {
                            model: [
                                { id: "left", label: qsTr("Left of") },
                                { id: "right", label: qsTr("Right of") },
                                { id: "above", label: qsTr("Above") },
                                { id: "below", label: qsTr("Below") }
                            ]
                            delegate: RyokuButton {
                                required property var modelData
                                text: modelData.label
                                variant: "tonal"
                                enabled: !displayModel.previewActive
                                         && selectedDraft.enabled !== false
                                         && root.relativeTarget.length > 0
                                onClicked: {
                                    displayModel.applyPositionPreset(modelData.id, root.relativeTarget)
                                    root.markDirty()
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    Column {
                        Layout.fillWidth: true
                        spacing: RyokuTheme.spacing_xxs
                        Text {
                            text: qsTr("Enabled")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            text: qsTr("At least one monitor must stay on.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                    RyokuToggle {
                        checked: selectedDraft.enabled !== false
                        enabled: !displayModel.previewActive
                        onToggled: function(v) {
                            displayModel.setDraftEnabled(v)
                            root.markDirty()
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Preview Changes")
                        variant: "primary"
                        enabled: displayModel.draftDirty && !displayModel.previewActive
                        onClicked: {
                            root.errorMessage = ""
                            root.runtimeNote = ""
                            displayModel.previewChanges()
                        }
                    }
                    RyokuButton {
                        text: qsTr("Reset draft")
                        variant: "ghost"
                        enabled: displayModel.draftDirty && !displayModel.previewActive
                        onClicked: {
                            displayModel.resetDraftFromRuntime()
                            root.dirty = false
                            root.errorMessage = ""
                        }
                    }
                    RyokuButton {
                        text: qsTr("Save to Ryoku")
                        variant: "secondary"
                        enabled: !displayModel.previewActive
                        onClicked: root.saveToRyoku()
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Preview applies for 15 seconds with auto-revert. Save writes settings.json only.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }
    }

    RyokuDialog {
        id: confirmDialog
        title: qsTr("Keep these display settings?")
        maxWidth: 420
        dialogClosePolicy: Popup.NoAutoClose

        Column {
            width: confirmDialog.availableWidth
            spacing: RyokuTheme.spacing_sm
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Reverting automatically in %1 seconds.")
                      .arg(displayModel.previewSecondsLeft)
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Keep to apply permanently, or Revert to restore the previous layout.")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }
        }

        footerComponent: Row {
            spacing: RyokuTheme.spacing_sm
            layoutDirection: Qt.RightToLeft
            width: confirmDialog.availableWidth
            RyokuButton {
                text: qsTr("Keep changes")
                variant: "primary"
                onClicked: displayModel.keepChanges()
            }
            RyokuButton {
                text: qsTr("Revert")
                variant: "secondary"
                onClicked: displayModel.revertPreview()
            }
        }
    }
}
