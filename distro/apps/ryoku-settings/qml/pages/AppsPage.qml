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

    property var draftDeclared: []
    property bool dirty: false
    property string errorMessage: ""
    property string addAppId: ""

    function seedFromStore() {
        draftDeclared = settingsStore.flatpakDeclared.slice()
        dirty = false
        errorMessage = ""
        flatpakApps.declaredIds = draftDeclared
    }

    function markDirty() {
        dirty = true
        errorMessage = ""
        flatpakApps.declaredIds = draftDeclared
    }

    // Draft vs declarative apply — ApplyController is the only apply-state source.
    readonly property string statusLabel: {
        if (errorMessage.length > 0)
            return qsTr("Error")
        if (dirty)
            return qsTr("Unsaved changes")
        if (applyController.needsSystemApply
            || applyController.status === "NeedsApply"
            || applyController.status === "Ready"
            || applyController.status === "ValidationFailed"
            || applyController.status === "AuthorizationDenied"
            || applyController.status === "AuthorizationError"
            || applyController.status === "ApplyFailed"
            || applyController.status === "RollbackFailed"
            || applyController.status === "AwaitingAuthorization"
            || applyController.status === "Applying"
            || applyController.status === "Validating"
            || applyController.status === "RollingBack")
            return qsTr("Needs Apply")
        if (applyController.status === "Applied")
            return qsTr("Applied")
        return qsTr("Clean")
    }

    readonly property string statusKind: {
        if (errorMessage.length > 0)
            return "error"
        if (dirty)
            return "modified"
        if (statusLabel === qsTr("Needs Apply"))
            return "needs_apply"
        if (statusLabel === qsTr("Applied"))
            return "applied"
        return "neutral"
    }

    function badgeForStatus(status, statusLabel) {
        // FlatpakAppsModel::Status — Managed=0, Pending=1, Local=2
        if (status === 1)
            return { text: qsTr("Pending install"), kind: "needs_apply" }
        if (status === 0)
            return { text: qsTr("Managed"), kind: "applied" }
        return { text: qsTr("Local"), kind: "neutral" }
    }

    function addToRyoku(appId) {
        const next = draftDeclared.slice()
        if (next.indexOf(appId) >= 0)
            return
        next.push(appId)
        next.sort()
        draftDeclared = next
        markDirty()
    }

    function removeFromRyoku(appId) {
        const next = draftDeclared.filter(function(id) { return id !== appId })
        draftDeclared = next
        markDirty()
    }

    function tryAddFromField() {
        errorMessage = ""
        const id = addAppId.trim()
        if (!id.length)
            return
        // Same rules as SettingsStore::isValidFlatpakId (presentation-side pre-check).
        const re = /^[A-Za-z0-9][A-Za-z0-9._-]*(\.[A-Za-z0-9][A-Za-z0-9._-]*)+$/
        if (!re.test(id)) {
            errorMessage = qsTr("Invalid Flatpak application ID")
            return
        }
        addToRyoku(id)
        addAppId = ""
    }

    function resetDraft() {
        seedFromStore()
    }

    function saveDraft() {
        errorMessage = ""
        if (!settingsStore.saveFlatpakDeclared(draftDeclared)) {
            errorMessage = settingsStore.lastWriteError.length
                           ? settingsStore.lastWriteError
                           : qsTr("Save failed")
            return
        }
        dirty = false
        draftDeclared = settingsStore.flatpakDeclared.slice()
        flatpakApps.declaredIds = draftDeclared
        gitStatus.refresh()
    }

    Component.onCompleted: {
        seedFromStore()
        flatpakApps.refresh()
    }

    Connections {
        target: settingsStore
        function onChanged() {
            if (!root.dirty)
                root.seedFromStore()
        }
        function onExternalChangePendingChanged() {
            if (!settingsStore.externalChangePending)
                return
            if (!root.dirty)
                settingsStore.acknowledgeExternalChange()
        }
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: RyokuTheme.spacing_md

        ColumnLayout {
            Layout.fillWidth: true
            spacing: RyokuTheme.spacing_xxs
            RowLayout {
                Layout.fillWidth: true
                spacing: RyokuTheme.spacing_sm
                Text {
                    text: qsTr("Apps")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                    Layout.fillWidth: true
                }
                RyokuBadge {
                    text: qsTr("%1 managed").arg(flatpakApps.managedCount)
                    kind: "applied"
                }
                RyokuBadge {
                    visible: flatpakApps.pendingCount > 0
                    text: qsTr("%1 pending").arg(flatpakApps.pendingCount)
                    kind: "needs_apply"
                }
                RyokuBadge {
                    text: root.statusLabel
                    kind: root.statusKind
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Manage declarative applications")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        Text {
            Layout.fillWidth: true
            visible: settingsStore.externalChangePending && root.dirty
            wrapMode: Text.WordWrap
            text: qsTr("Configuration changed externally.")
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
            visible: flatpakApps.error.length > 0
            wrapMode: Text.WordWrap
            text: flatpakApps.error
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── Changes ───────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Changes")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.dirty
                          ? qsTr("You have unsaved app list changes. Save and applying to the system are separate steps.")
                          : qsTr("Saved list matches the draft. Applying to the system is separate from Save.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Refresh")
                        variant: "ghost"
                        onClicked: flatpakApps.refresh()
                    }
                    RyokuButton {
                        text: qsTr("Reset Changes")
                        variant: "ghost"
                        enabled: root.dirty
                        onClicked: root.resetDraft()
                    }
                    RyokuButton {
                        text: qsTr("Save Changes")
                        variant: "primary"
                        enabled: root.dirty
                        onClicked: root.saveDraft()
                    }
                }
            }
        }

        // ── Add ───────────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Add Flatpak")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Flatpak application ID")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_body
                    font.bold: true
                }
                TextField {
                    id: addField
                    width: parent.width
                    text: root.addAppId
                    onTextChanged: root.addAppId = text
                    placeholderText: qsTr("e.g. org.mozilla.firefox")
                    color: RyokuTheme.on_surface
                    Keys.onReturnPressed: root.tryAddFromField()
                    background: Rectangle {
                        color: RyokuTheme.glass_surface_high
                        radius: RyokuTheme.radius_sm
                        border.color: RyokuTheme.glass_border
                        border.width: RyokuTheme.border_width
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Changes are applied declaratively after Save and Apply.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                RyokuButton {
                    text: qsTr("Add")
                    variant: "tonal"
                    enabled: root.addAppId.trim().length > 0
                    onClicked: root.tryAddFromField()
                }
            }
        }

        // ── Managed ───────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Managed by Ryoku")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    model: flatpakApps
                    delegate: RyokuDeviceRow {
                        required property string applicationId
                        required property string name
                        required property int status
                        required property string statusLabel
                        required property bool declared
                        width: parent.width
                        height: declared ? implicitHeight : 0
                        visible: declared
                        leading: "▦"
                        title: name.length ? name : applicationId
                        subtitle: name.length ? applicationId : statusLabel
                        badgeText: root.badgeForStatus(status, statusLabel).text
                        badgeKind: root.badgeForStatus(status, statusLabel).kind
                        actionLabel: qsTr("Remove")
                        actionVariant: "secondary"
                        onActionClicked: root.removeFromRyoku(applicationId)
                    }
                }

                Text {
                    visible: flatpakApps.managedCount + flatpakApps.pendingCount === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("No Flatpaks declared yet.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Remove updates the declarative list only — it does not uninstall Flatpak packages.")
            color: RyokuTheme.on_surface_muted
            font.pixelSize: RyokuTheme.font_caption
        }

        // ── Local ─────────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Installed locally")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_xs

                Repeater {
                    model: flatpakApps
                    delegate: RyokuDeviceRow {
                        required property string applicationId
                        required property string name
                        required property int status
                        required property string statusLabel
                        required property bool declared
                        width: parent.width
                        height: !declared ? implicitHeight : 0
                        visible: !declared
                        leading: "▦"
                        title: name.length ? name : applicationId
                        subtitle: name.length ? applicationId : qsTr("Unmanaged")
                        badgeText: qsTr("Local")
                        badgeKind: "neutral"
                        actionLabel: qsTr("Add to Ryoku")
                        actionVariant: "tonal"
                        onActionClicked: root.addToRyoku(applicationId)
                    }
                }

                Text {
                    visible: flatpakApps.localCount === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("No unmanaged Flatpaks installed.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }
    }
}
