import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    property bool showRepoDetails: false
    property bool showUpdateDetails: false
    property bool showGenDetails: false
    property bool showGitPanel: false
    property bool showCommitConfirm: false
    property string commitMessage: ""
    property var gitSelected: ({})
    property int confirmSwitchGeneration: -1
    property var confirmSwitchData: ({})

    function gitSelKey(section, path) {
        return section + "\0" + path
    }
    function isGitSelected(section, path) {
        return !!root.gitSelected[root.gitSelKey(section, path)]
    }
    function toggleGitSelected(section, path) {
        const k = root.gitSelKey(section, path)
        const next = Object.assign({}, root.gitSelected)
        if (next[k])
            delete next[k]
        else
            next[k] = true
        root.gitSelected = next
    }
    function clearGitSelected() {
        root.gitSelected = ({})
    }
    function selectedPathsIn(section) {
        const prefix = section + "\0"
        const out = []
        for (const k of Object.keys(root.gitSelected)) {
            if (k.indexOf(prefix) === 0)
                out.push(k.slice(prefix.length))
        }
        return out
    }
    function openGitPanel() {
        root.clearGitSelected()
        root.commitMessage = ""
        root.showCommitConfirm = false
        gitStatus.clearDiff()
        gitStatus.refresh()
        root.showGitPanel = true
    }
    function closeGitPanel() {
        root.showGitPanel = false
        root.showCommitConfirm = false
        root.clearGitSelected()
        gitStatus.clearDiff()
    }
    function askCommit() {
        const preview = gitStatus.commitPreview()
        if (!preview.canCommit)
            return
        root.showCommitConfirm = true
    }
    function confirmCommit() {
        root.showCommitConfirm = false
        gitStatus.commit(root.commitMessage)
        root.commitMessage = ""
        root.clearGitSelected()
    }

    function askSwitchGeneration(gen) {
        const preview = applyController.generationSwitchPreview(gen)
        const row = generationsModel.generationAt(gen)
        root.confirmSwitchGeneration = gen
        root.confirmSwitchData = {
            generation: gen,
            date: row.date || "",
            nixosVersion: row.nixosVersion || "",
            kernelVersion: row.kernelVersion || "",
            canSwitch: preview.canSwitch === true,
            error: preview.error || ""
        }
    }

    function cancelSwitchConfirm() {
        root.confirmSwitchGeneration = -1
        root.confirmSwitchData = ({})
    }

    function confirmSwitch() {
        const gen = root.confirmSwitchGeneration
        root.cancelSwitchConfirm()
        if (gen > 0)
            applyController.switchGeneration(gen)
    }

    Component.onCompleted: root.refreshAll()

    function refreshAll() {
        gitStatus.refresh()
        flakeMetadata.refresh()
        flakeUpdate.refresh()
        generationsModel.refresh()
        applyController.refresh()
        systemInfo.refresh()
    }


    function shortRev(rev) {
        if (!rev || !rev.length)
            return ""
        return rev.length > 12 ? rev.slice(0, 12) : rev
    }

    function applyKind() {
        const st = applyController.status
        if (st === "Applied")
            return "applied"
        if (st === "NeedsApply" || st === "Ready" || applyController.lockfilePendingRebuild)
            return "needs_apply"
        if (st === "ApplyFailed" || st === "SwitchFailed" || st === "HashError")
            return "error"
        return "neutral"
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
                    Layout.fillWidth: true
                    text: qsTr("Nix & Updates")
                    color: RyokuTheme.on_background
                    font.pixelSize: RyokuTheme.font_title
                    font.bold: true
                }
                RyokuButton {
                    text: qsTr("Refresh")
                    variant: "ghost"
                    enabled: !flakeUpdate.busy
                    onClicked: root.refreshAll()
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Repository, flake updates, system apply and generations")
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_body
            }
        }

        // 1) Repository / Git
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Repository")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                GridLayout {
                    width: parent.width
                    columns: root.width >= 720 ? 2 : 1
                    columnSpacing: RyokuTheme.spacing_md
                    rowSpacing: RyokuTheme.spacing_sm

                    RyokuSettingRow {
                        Layout.fillWidth: true
                        label: qsTr("Branch")
                        value: {
                            if (!gitStatus.available)
                                return qsTr("Unavailable")
                            if (gitStatus.detachedHead)
                                return qsTr("Detached HEAD")
                            return gitStatus.branch || qsTr("Unavailable")
                        }
                    }
                    RyokuSettingRow {
                        Layout.fillWidth: true
                        label: qsTr("Working tree")
                        value: gitStatus.workingTreeLabel
                        hint: gitStatus.error
                    }
                    RyokuSettingRow {
                        Layout.fillWidth: true
                        Layout.columnSpan: root.width >= 720 ? 2 : 1
                        label: qsTr("HEAD")
                        value: gitStatus.available ? gitStatus.headSummaryText : qsTr("Unavailable")
                    }
                    RyokuSettingRow {
                        Layout.fillWidth: true
                        Layout.columnSpan: root.width >= 720 ? 2 : 1
                        label: qsTr("Remote")
                        value: gitStatus.pushStatusLabel
                    }
                }

                Text {
                    visible: flakeUpdate.repoWasDirtyBeforeUpdate && flakeUpdate.pendingLockChange
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Repo was already modified before this update.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Manage changes")
                        variant: "primary"
                        enabled: gitStatus.available && !gitStatus.busy
                        onClicked: root.openGitPanel()
                    }
                    RyokuButton {
                        text: qsTr("Fetch")
                        variant: "secondary"
                        enabled: gitStatus.canFetch
                        onClicked: gitStatus.fetch()
                    }
                    RyokuButton {
                        text: qsTr("Push")
                        variant: "tonal"
                        enabled: gitStatus.canPush
                        onClicked: gitStatus.push()
                    }
                }

                Text {
                    visible: gitStatus.successMessage.length > 0
                    width: parent.width
                    text: gitStatus.successMessage
                    color: RyokuTheme.primary
                    font.pixelSize: RyokuTheme.font_caption
                    wrapMode: Text.WordWrap
                }
            }
        }

        // 2) Flake updates
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Flake inputs")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Check is read-only. Update changes flake.lock only — it does not rebuild the system.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Check for updates")
                        variant: "secondary"
                        enabled: !flakeUpdate.busy
                        onClicked: flakeUpdate.checkForUpdates()
                    }
                    RyokuButton {
                        text: qsTr("Update all")
                        variant: "tonal"
                        enabled: !flakeUpdate.busy
                        onClicked: {
                            flakeUpdate.repoWasDirtyBeforeUpdate = !gitStatus.clean
                            flakeUpdate.updateAll()
                        }
                    }
                }

                RyokuSettingRow {
                    label: qsTr("Status")
                    value: flakeUpdate.statusLabel
                    hint: flakeUpdate.error
                }

                Repeater {
                    model: flakeUpdate.inputs.length ? flakeUpdate.inputs : flakeMetadata.inputs
                    delegate: RyokuDeviceRow {
                        required property var modelData
                        width: parent.width
                        leading: "❄"
                        title: modelData.name || ""
                        subtitle: {
                            const parts = []
                            if (modelData.statusLabel)
                                parts.push(modelData.statusLabel)
                            else if (modelData.summary)
                                parts.push(modelData.summary)
                            const rev = modelData.revision || modelData.lockedRev || ""
                            if (rev.length)
                                parts.push(root.shortRev(rev))
                            return parts.join(" · ")
                        }
                        badgeText: {
                            const s = modelData.status || ""
                            if (s === "update_available")
                                return qsTr("Update available")
                            if (s === "up_to_date")
                                return qsTr("Up to date")
                            return ""
                        }
                        badgeKind: {
                            const s = modelData.status || ""
                            if (s === "update_available")
                                return "needs_apply"
                            if (s === "up_to_date")
                                return "applied"
                            return "neutral"
                        }
                        actionLabel: qsTr("Update")
                        actionVariant: "tonal"
                        showAction: !!modelData.name
                        onActionClicked: {
                            if (flakeUpdate.busy || !modelData.name)
                                return
                            flakeUpdate.repoWasDirtyBeforeUpdate = !gitStatus.clean
                            flakeUpdate.updateInput(modelData.name)
                        }
                    }
                }

                Text {
                    visible: flakeUpdate.inputs.length === 0 && flakeMetadata.inputs.length === 0
                    width: parent.width
                    text: qsTr("No inputs loaded — Refresh")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Pending lockfile changes")
            visible: flakeUpdate.pendingLockChange || flakeUpdate.canRevert
                     || flakeUpdate.lockDiff.length > 0

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                RyokuBadge {
                    text: applyController.lockfilePendingRebuild || flakeUpdate.pendingLockChange
                          ? qsTr("Updates downloaded · Rebuild required")
                          : qsTr("Pending")
                    kind: "needs_apply"
                }

                RyokuSettingRow {
                    label: qsTr("Validation")
                    value: flakeUpdate.validationLabel
                }

                Repeater {
                    model: flakeUpdate.lockDiff
                    delegate: RyokuSettingRow {
                        required property var modelData
                        width: parent.width
                        label: modelData.name || ""
                        value: modelData.label || ""
                    }
                }

                Text {
                    visible: flakeUpdate.lockDiff.length === 0 && flakeUpdate.pendingLockChange
                    width: parent.width
                    text: qsTr("Lockfile changed (no per-input rev diff detected)")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Validate")
                        variant: "secondary"
                        enabled: flakeUpdate.canValidatePending
                        onClicked: flakeUpdate.validatePending()
                    }
                    RyokuButton {
                        text: qsTr("Revert update")
                        variant: "ghost"
                        enabled: flakeUpdate.canRevert && !flakeUpdate.busy
                        onClicked: flakeUpdate.revertUpdate()
                    }
                    RyokuButton {
                        text: root.showUpdateDetails ? qsTr("Hide details") : qsTr("Details")
                        variant: "ghost"
                        onClicked: root.showUpdateDetails = !root.showUpdateDetails
                    }
                }

                Text {
                    visible: root.showUpdateDetails && flakeUpdate.details.length > 0
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: flakeUpdate.details
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_mono
                    font.family: "monospace"
                    maximumLineCount: 24
                    elide: Text.ElideRight
                }
            }
        }

        // 3) System state (summary — not full Apply banner)
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("System state")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                RowLayout {
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Ryoku settings")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    RyokuBadge {
                        text: applyController.statusText
                        kind: root.applyKind()
                    }
                }

                RyokuSettingRow {
                    label: qsTr("Flake lock")
                    value: applyController.lockfilePendingRebuild
                           ? qsTr("Changed — rebuild required")
                           : (flakeUpdate.pendingLockChange
                              ? qsTr("Changed — Apply recommended")
                              : qsTr("Current"))
                }
                RyokuSettingRow {
                    label: qsTr("Generation")
                    value: {
                        const g = generationsModel.currentGeneration >= 0
                                  ? generationsModel.currentGeneration
                                  : systemInfo.profileGeneration
                        return g >= 0 ? qsTr("Generation %1").arg(g) : qsTr("Unavailable")
                    }
                }
                RyokuSettingRow {
                    label: qsTr("Rebuild hint")
                    value: flakeUpdate.lockfileRebuildHint.length
                           ? flakeUpdate.lockfileRebuildHint
                           : qsTr("—")
                    hint: flakeUpdate.runningNixpkgsHint
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Use the global Apply banner to validate and rebuild. Updating the lock does not apply the system.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
            }
        }

        // 4) Generations
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Generations")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Switch activates an existing NixOS generation. Repository files are not modified.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                RyokuButton {
                    text: qsTr("Rollback to previous generation")
                    variant: "secondary"
                    enabled: applyController.canRollback && !applyController.busy
                    onClicked: applyController.rollback()
                }

                Text {
                    visible: generationsModel.error.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: generationsModel.error
                    color: RyokuTheme.error
                    font.pixelSize: RyokuTheme.font_caption
                }
                RyokuButton {
                    visible: generationsModel.error.length > 0
                    text: qsTr("Retry")
                    variant: "ghost"
                    onClicked: generationsModel.refresh()
                }

                Text {
                    visible: applyController.progressStage.length > 0
                             && (applyController.status === "SwitchingGeneration"
                                 || applyController.status === "AwaitingAuthorization"
                                 || applyController.status === "RollingBack")
                    width: parent.width
                    text: applyController.progressStage
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_body
                }

                Repeater {
                    model: generationsModel.generations
                    delegate: RyokuDeviceRow {
                        required property var modelData
                        width: parent.width
                        leading: "⚙"
                        title: qsTr("Generation %1").arg(modelData.generation)
                        subtitle: {
                            let t = modelData.date || ""
                            if (modelData.nixosVersion)
                                t += (t.length ? " · " : "") + modelData.nixosVersion
                            if (modelData.kernelVersion)
                                t += (t.length ? " · " : "") + ("Kernel " + modelData.kernelVersion)
                            return t
                        }
                        badgeText: (modelData.current || modelData.isProfile)
                                   ? (modelData.relationLabel || qsTr("Current"))
                                   : ""
                        badgeKind: "current"
                        highlighted: !!(modelData.current || modelData.isProfile)
                        actionLabel: qsTr("Switch")
                        actionVariant: "tonal"
                        showAction: !modelData.current
                        onActionClicked: {
                            if (applyController.busy)
                                return
                            if (!applyController.canSwitchGeneration(modelData.generation))
                                return
                            root.askSwitchGeneration(modelData.generation)
                        }
                        onClicked: {
                            root.showGenDetails = true
                            root.confirmSwitchData = modelData
                            root.confirmSwitchGeneration = -2
                        }
                    }
                }
            }
        }
    }

    // Confirm switch — glass overlay (logic unchanged)
    Rectangle {
        visible: root.confirmSwitchGeneration > 0
        anchors.fill: parent
        color: RyokuTheme.scrim
        z: 100
        MouseArea { anchors.fill: parent; onClicked: root.cancelSwitchConfirm() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 420)
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border
            implicitHeight: confirmCol.implicitHeight + RyokuTheme.spacing_md * 2
            Column {
                id: confirmCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: RyokuTheme.spacing_md
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Switch to Generation %1?").arg(root.confirmSwitchGeneration)
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_section
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("This will activate an existing NixOS system generation.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_body
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Generation %1\n%2\nNixOS %3\nKernel %4")
                          .arg(root.confirmSwitchData.generation || "")
                          .arg(root.confirmSwitchData.date || "—")
                          .arg(root.confirmSwitchData.nixosVersion || "—")
                          .arg(root.confirmSwitchData.kernelVersion || "—")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_body
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Your current Ryoku repository files will NOT be modified.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                Row {
                    spacing: RyokuTheme.spacing_sm
                    layoutDirection: Qt.RightToLeft
                    width: parent.width
                    RyokuButton {
                        text: qsTr("Switch")
                        variant: "primary"
                        enabled: root.confirmSwitchData.canSwitch !== false
                        onClicked: root.confirmSwitch()
                    }
                    RyokuButton {
                        text: qsTr("Cancel")
                        variant: "secondary"
                        onClicked: root.cancelSwitchConfirm()
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.confirmSwitchGeneration === -2
        anchors.fill: parent
        color: RyokuTheme.scrim
        z: 100
        MouseArea { anchors.fill: parent; onClicked: root.cancelSwitchConfirm() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 420)
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border
            implicitHeight: detailsCol.implicitHeight + RyokuTheme.spacing_md * 2
            Column {
                id: detailsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: RyokuTheme.spacing_md
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    text: qsTr("Generation %1").arg(root.confirmSwitchData.generation || "")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_section
                    font.bold: true
                }
                RyokuSettingRow { label: qsTr("Date"); value: root.confirmSwitchData.date || "—" }
                RyokuSettingRow { label: qsTr("NixOS"); value: root.confirmSwitchData.nixosVersion || "—" }
                RyokuSettingRow { label: qsTr("Kernel"); value: root.confirmSwitchData.kernelVersion || "—" }
                RyokuSettingRow { label: qsTr("Revision"); value: root.confirmSwitchData.configurationRevision || "—" }
                RyokuButton {
                    text: qsTr("Close")
                    variant: "secondary"
                    onClicked: root.cancelSwitchConfirm()
                }
            }
        }
    }

    // Git Manage Changes panel
    Rectangle {
        visible: root.showGitPanel
        anchors.fill: parent
        color: RyokuTheme.scrim
        z: 110
        MouseArea { anchors.fill: parent; onClicked: root.closeGitPanel() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 16, 720)
            height: Math.min(parent.height - 24, 640)
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border
            clip: true
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: RyokuTheme.spacing_md
                spacing: RyokuTheme.spacing_sm

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Git changes")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_section
                        font.bold: true
                    }
                    Text {
                        text: gitStatus.busy ? gitStatus.operationPhase : ""
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    RyokuButton {
                        text: qsTr("Close")
                        variant: "ghost"
                        onClicked: root.closeGitPanel()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: gitStatus.hasConflicts
                    wrapMode: Text.WordWrap
                    text: qsTr("Resolve conflicts outside Ryoku Settings before committing.")
                    color: RyokuTheme.error
                    font.pixelSize: RyokuTheme.font_caption
                }
                Text {
                    Layout.fillWidth: true
                    visible: gitStatus.detachedHead
                    wrapMode: Text.WordWrap
                    text: qsTr("Detached HEAD — commit and push are disabled.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                Text {
                    Layout.fillWidth: true
                    visible: gitStatus.error.length > 0
                    wrapMode: Text.WordWrap
                    text: gitStatus.error
                    color: RyokuTheme.error
                    font.pixelSize: RyokuTheme.font_caption
                }
                Text {
                    Layout.fillWidth: true
                    visible: gitStatus.successMessage.length > 0
                    wrapMode: Text.WordWrap
                    text: gitStatus.successMessage
                    color: RyokuTheme.primary
                    font.pixelSize: RyokuTheme.font_caption
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: RyokuTheme.spacing_sm

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.horizontalStretchFactor: 48
                        Layout.fillHeight: true
                        contentHeight: filesCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: filesCol
                            width: parent.width
                            spacing: RyokuTheme.spacing_sm

                            component FileSection: Column {
                                property string title
                                property var entries
                                property string section
                                width: parent.width
                                spacing: RyokuTheme.spacing_xxs
                                Text {
                                    text: title + " (" + entries.length + ")"
                                    color: RyokuTheme.on_surface
                                    font.pixelSize: RyokuTheme.font_body
                                    font.bold: true
                                }
                                Text {
                                    visible: entries.length === 0
                                    text: qsTr("None")
                                    color: RyokuTheme.on_surface_muted
                                    font.pixelSize: RyokuTheme.font_caption
                                }
                                Repeater {
                                    model: entries
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: parent.width
                                        height: row.implicitHeight + 8
                                        radius: RyokuTheme.radius_sm
                                        color: root.isGitSelected(section, modelData.path)
                                               ? RyokuTheme.primary_tint : "transparent"
                                        Row {
                                            id: row
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: RyokuTheme.spacing_xs
                                            RyokuToggle {
                                                checked: root.isGitSelected(section, modelData.path)
                                                onToggled: root.toggleGitSelected(section, modelData.path)
                                            }
                                            Text {
                                                text: (modelData.code || "?")
                                                color: RyokuTheme.primary
                                                font.pixelSize: RyokuTheme.font_caption
                                                font.bold: true
                                                width: 18
                                            }
                                            Column {
                                                width: parent.width - 90
                                                Text {
                                                    width: parent.width
                                                    text: modelData.path || ""
                                                    color: RyokuTheme.on_surface
                                                    font.pixelSize: RyokuTheme.font_caption
                                                    elide: Text.ElideMiddle
                                                }
                                                Text {
                                                    width: parent.width
                                                    text: section
                                                    color: RyokuTheme.on_surface_muted
                                                    font.pixelSize: RyokuTheme.font_caption
                                                }
                                            }
                                            MouseArea {
                                                width: parent.width
                                                height: parent.height
                                                z: -1
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: gitStatus.loadDiff(modelData.path, section === "staged")
                                            }
                                        }
                                    }
                                }
                            }

                            FileSection { title: qsTr("Staged"); entries: gitStatus.stagedEntries; section: "staged" }
                            FileSection { title: qsTr("Changes"); entries: gitStatus.unstagedEntries; section: "unstaged" }
                            FileSection { title: qsTr("Untracked"); entries: gitStatus.untrackedEntries; section: "untracked" }
                            FileSection {
                                visible: gitStatus.conflictEntries.length > 0
                                title: qsTr("Conflicts")
                                entries: gitStatus.conflictEntries
                                section: "conflict"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.horizontalStretchFactor: 52
                        Layout.fillHeight: true
                        color: RyokuTheme.glass_surface_high
                        radius: RyokuTheme.radius_md
                        border.width: RyokuTheme.border_width
                        border.color: RyokuTheme.glass_border
                        clip: true
                        Flickable {
                            anchors.fill: parent
                            anchors.margins: RyokuTheme.spacing_sm
                            contentHeight: diffLabel.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            Text {
                                id: diffLabel
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                font.family: "monospace"
                                font.pixelSize: RyokuTheme.font_mono
                                color: RyokuTheme.on_surface
                                text: {
                                    if (!gitStatus.diffPath.length)
                                        return qsTr("Select a file to view diff (read-only).")
                                    let h = (gitStatus.diffStaged ? "staged" : "unstaged")
                                            + " · " + gitStatus.diffPath
                                    if (gitStatus.diffBinary)
                                        return h + "\n\n" + qsTr("Binary file changed")
                                    return h + "\n\n" + (gitStatus.diffText || "")
                                }
                            }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Stage selected")
                        variant: "tonal"
                        enabled: !gitStatus.busy
                                 && (root.selectedPathsIn("unstaged").length
                                     + root.selectedPathsIn("untracked").length) > 0
                        onClicked: {
                            const paths = root.selectedPathsIn("unstaged")
                                          .concat(root.selectedPathsIn("untracked"))
                            gitStatus.stagePaths(paths)
                            root.clearGitSelected()
                        }
                    }
                    RyokuButton {
                        text: qsTr("Unstage selected")
                        variant: "ghost"
                        enabled: !gitStatus.busy && root.selectedPathsIn("staged").length > 0
                        onClicked: {
                            gitStatus.unstagePaths(root.selectedPathsIn("staged"))
                            root.clearGitSelected()
                        }
                    }
                    RyokuButton {
                        text: qsTr("Refresh")
                        variant: "ghost"
                        enabled: !gitStatus.busy
                        onClicked: gitStatus.refresh()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Commit message")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_caption
                    font.bold: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    radius: RyokuTheme.radius_sm
                    color: RyokuTheme.glass_surface_high
                    border.width: RyokuTheme.border_width
                    border.color: RyokuTheme.glass_border
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: RyokuTheme.spacing_sm
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        clip: true
                        text: root.commitMessage
                        onTextChanged: root.commitMessage = text
                        enabled: !gitStatus.busy && !gitStatus.detachedHead
                    }
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Commit")
                        variant: "primary"
                        enabled: gitStatus.canCommit && root.commitMessage.trim().length > 0
                        onClicked: root.askCommit()
                    }
                    RyokuButton {
                        text: qsTr("Push")
                        variant: "secondary"
                        enabled: gitStatus.canPush
                        onClicked: gitStatus.push()
                    }
                    RyokuButton {
                        text: qsTr("Fetch")
                        variant: "ghost"
                        enabled: gitStatus.canFetch
                        onClicked: gitStatus.fetch()
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    contentHeight: detailsGit.implicitHeight
                    clip: true
                    Text {
                        id: detailsGit
                        width: parent.width
                        text: gitStatus.details
                        wrapMode: Text.WrapAnywhere
                        font.family: "monospace"
                        font.pixelSize: RyokuTheme.font_mono
                        color: RyokuTheme.on_surface_muted
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.showCommitConfirm
        anchors.fill: parent
        color: RyokuTheme.scrim
        z: 120
        MouseArea { anchors.fill: parent; onClicked: root.showCommitConfirm = false }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 420)
            radius: RyokuTheme.radius_lg
            color: RyokuTheme.glass_surface
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.glass_border
            implicitHeight: commitConfirmCol.implicitHeight + RyokuTheme.spacing_md * 2
            Column {
                id: commitConfirmCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: RyokuTheme.spacing_md
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Commit %1 staged files?").arg(gitStatus.stagedCount)
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_section
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: (gitStatus.commitPreview().stagedPaths || []).join("\n")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Message: %1").arg(root.commitMessage.trim())
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_body
                }
                Row {
                    spacing: RyokuTheme.spacing_sm
                    layoutDirection: Qt.RightToLeft
                    width: parent.width
                    RyokuButton {
                        text: qsTr("Commit")
                        variant: "primary"
                        onClicked: root.confirmCommit()
                    }
                    RyokuButton {
                        text: qsTr("Cancel")
                        variant: "secondary"
                        onClicked: root.showCommitConfirm = false
                    }
                }
            }
        }
    }


    Connections {
        target: flakeUpdate
        function onLockfileChanged() {
            gitStatus.refresh()
            flakeMetadata.refresh()
        }
    }

    Connections {
        target: applyController
        function onChanged() {
            if (applyController.status === "NeedsApply"
                || applyController.status === "Applied"
                || applyController.status === "SwitchFailed")
                generationsModel.refresh()
        }
    }
}
