import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ryoku.Settings

ApplicationWindow {
    id: root
    visible: true
    width: 1080
    height: 700
    minimumWidth: 840
    minimumHeight: 560
    title: qsTr("Ryoku Settings")
    color: RyokuTheme.background

    // Inject C++ PaletteManager into the theme singleton (reactive bindings).
    // Must NOT use the name "palette" — that is ApplicationWindow.palette.
    Binding {
        target: RyokuTheme
        property: "paletteManager"
        value: paletteManager
    }

    // Motion follows the same visual profile as the shell (DMS RyokuVisual).
    Binding {
        target: RyokuTheme
        property: "visual_profile"
        value: {
            const p = settingsStore.visualProfileValue
            return (p === "economy" || p === "cinematic") ? p : "balanced"
        }
    }

    // Adaptation for any remaining Qt Quick Controls — not the Ryoku SoT.
    palette {
        window: RyokuTheme.background
        windowText: RyokuTheme.on_background
        base: RyokuTheme.surface_container
        alternateBase: RyokuTheme.surface_container_high
        text: RyokuTheme.on_surface
        placeholderText: RyokuTheme.on_surface_muted
        button: RyokuTheme.surface_container
        buttonText: RyokuTheme.on_surface
        highlight: RyokuTheme.primary
        highlightedText: RyokuTheme.on_primary
        toolTipBase: RyokuTheme.surface_container_high
        toolTipText: RyokuTheme.on_surface
    }

    // `source` is the untranslated title, so search also matches English words.
    readonly property var pages: [
        { id: "home", title: qsTr("Home"), source: "Home", icon: "home" },
        { id: "appearance", title: qsTr("Appearance"), source: "Appearance", icon: "palette" },
        { id: "network", title: qsTr("Network"), source: "Network", icon: "wifi" },
        { id: "bluetooth", title: qsTr("Bluetooth"), source: "Bluetooth", icon: "bluetooth" },
        { id: "sound", title: qsTr("Sound"), source: "Sound", icon: "volume_up" },
        { id: "displays", title: qsTr("Displays"), source: "Displays", icon: "desktop_windows" },
        { id: "power", title: qsTr("Power"), source: "Power", icon: "power_settings_new" },
        { id: "apps", title: qsTr("Apps"), source: "Apps", icon: "apps" },
        { id: "system", title: qsTr("System"), source: "System", icon: "settings" },
        { id: "nix", title: qsTr("Nix & Updates"), source: "Nix & Updates", icon: "system_update_alt" },
        { id: "about", title: qsTr("About"), source: "About", icon: "info" }
    ]

    property int currentIndex: 0

    // ── Page navigation / transition ──────────────────────────────────────
    property int previousIndex: 0
    // +1 = entering from the right (next), −1 = from the left (previous).
    property int transitionDirection: 1
    property int pendingDirection: 0

    function goToPage(index, direction) {
        const count = pages.length
        const next = ((index % count) + count) % count
        if (next === currentIndex)
            return
        pendingDirection = direction || 0
        currentIndex = next
    }
    function nextPage() { goToPage(currentIndex + 1, 1) }
    function previousPage() { goToPage(currentIndex - 1, -1) }

    onCurrentIndexChanged: {
        transitionDirection = pendingDirection !== 0
            ? pendingDirection
            : (currentIndex >= previousIndex ? 1 : -1)
        pendingDirection = 0
        previousIndex = currentIndex
        pageEnter.restart()
    }

    // ── Search ────────────────────────────────────────────────────────────
    readonly property bool searching: searchField.text.trim().length > 0
    readonly property var searchResults: {
        // Re-run when the UI language changes: labels come from qsTranslate().
        const _ = languageManager.language
        return searchIndex.search(searchField.text, pages)
    }
    property Item searchHighlightItem: null

    function focusSearch() {
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

    function moveSearchSelection(delta) {
        if (searchResults.length === 0)
            return
        const n = Math.max(0, Math.min(searchResults.length - 1, resultsList.currentIndex + delta))
        resultsList.currentIndex = n
        resultsList.positionViewAtIndex(n, ListView.Contain)
    }

    function closeSearch() {
        if (searchField.text.length > 0) {
            searchField.clear()
            return
        }
        const page = pageStack.children[currentIndex]
        if (page)
            page.forceActiveFocus()
    }

    function openSearchResult(result) {
        if (!result)
            return
        goToPage(result.pageIndex, 0)
        if (result.isPage)
            return
        const page = pageStack.children[result.pageIndex]
        if (page && result.reveal && typeof page.revealSearchTarget === "function")
            page.revealSearchTarget(result.reveal)
        revealTimer.result = result
        revealTimer.restart()
    }

    // Depth-first search for the visible label a result points at.
    function findLabel(item, label) {
        if (!item || !item.visible)
            return null
        if (typeof item.text === "string" && item.lineCount !== undefined && item.text === label)
            return item
        const kids = item.children
        for (let i = 0; i < kids.length; ++i) {
            const hit = findLabel(kids[i], label)
            if (hit)
                return hit
        }
        return null
    }

    function revealLabel(result) {
        const page = pageStack.children[result.pageIndex]
        const target = findLabel(page, result.label)
        if (!page || !target)
            return
        if (page.contentItem !== undefined && page.contentHeight !== undefined) {
            const p = target.mapToItem(page.contentItem, 0, 0)
            const maxY = Math.max(0, page.contentHeight - page.height)
            scrollAnim.target = page
            scrollAnim.to = Math.max(0, Math.min(maxY, p.y - page.height * 0.3))
            scrollAnim.restart()
        }
        if (searchHighlightItem)
            searchHighlightItem.destroy()
        searchHighlightItem = searchHighlight.createObject(target)
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: root.focusSearch()
    }
    Shortcut {
        sequences: ["Ctrl+Tab"]
        onActivated: root.nextPage()
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Shift+Backtab", "Ctrl+Backtab"]
        onActivated: root.previousPage()
    }

    RyokuSearchIndex { id: searchIndex }

    // Shared-axis enter: fade + small slide toward the navigation direction.
    ParallelAnimation {
        id: pageEnter
        NumberAnimation {
            target: pageStack
            property: "opacity"
            from: 0
            to: 1
            duration: RyokuTheme.motion_standard
            easing.type: Easing.BezierSpline
            easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
        }
        NumberAnimation {
            target: pageShift
            property: "x"
            from: root.transitionDirection * RyokuTheme.motion_offset
            to: 0
            duration: RyokuTheme.motion_standard
            easing.type: Easing.BezierSpline
            easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
        }
        NumberAnimation {
            target: pageStack
            property: "scale"
            from: RyokuTheme.profile_cinematic ? 0.985 : 1
            to: 1
            duration: RyokuTheme.motion_standard
            easing.type: Easing.BezierSpline
            easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
        }
    }

    // Layout of a freshly shown page settles on the next polish; one short shot.
    Timer {
        id: revealTimer
        property var result: null
        interval: 40
        repeat: false
        onTriggered: if (result) root.revealLabel(result)
    }

    NumberAnimation {
        id: scrollAnim
        property: "contentY"
        duration: RyokuTheme.motion_emphasized
        easing.type: Easing.BezierSpline
        easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
    }

    Component {
        id: searchHighlight
        Rectangle {
            id: hl
            anchors.fill: parent
            anchors.margins: -RyokuTheme.spacing_xxs
            z: -1
            radius: RyokuTheme.radius_sm
            color: RyokuTheme.primary_tint_strong
            border.width: RyokuTheme.border_width
            border.color: RyokuTheme.primary
            opacity: 0

            SequentialAnimation {
                running: true
                NumberAnimation {
                    target: hl
                    property: "opacity"
                    to: 1
                    duration: RyokuTheme.motion_fast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
                }
                PauseAnimation { duration: 900 }
                NumberAnimation {
                    target: hl
                    property: "opacity"
                    to: 0
                    duration: RyokuTheme.motion_emphasized
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_accelerate)
                }
                ScriptAction {
                    script: {
                        if (root.searchHighlightItem === hl)
                            root.searchHighlightItem = null
                        hl.destroy()
                    }
                }
            }
        }
    }

    // Appearance / Apps draft mirrored for Home status (Clean / Modified / Error).
    property bool appearanceDirty: false
    property string appearanceError: ""
    property bool appsDirty: false
    property string appsError: ""
    property bool displaysDirty: false
    property string displaysError: ""

    readonly property string ryokuConfigStatus: {
        if (!settingsStore.loaded || settingsStore.error.length > 0
            || appearanceError.length > 0 || appsError.length > 0
            || displaysError.length > 0)
            return qsTr("Error")
        if (appearanceDirty || appsDirty || displaysDirty)
            return qsTr("Unsaved")
        // Apply state only — never derive from Git dirty.
        if (applyController.status === "HashError")
            return qsTr("Hash error")
        if (applyController.status === "NeedsApply" || applyController.status === "Ready"
            || applyController.status === "ValidationFailed"
            || applyController.status === "AuthorizationDenied"
            || applyController.status === "AuthorizationError"
            || applyController.status === "ApplyFailed")
            return qsTr("Needs Apply")
        if (applyController.status === "AwaitingAuthorization")
            return qsTr("Waiting for authorization…")
        if (applyController.status === "Applying")
            return qsTr("Applying…")
        if (applyController.status === "RollingBack")
            return qsTr("Rolling back…")
        if (applyController.status === "SwitchingGeneration")
            return qsTr("Switching generation…")
        if (applyController.status === "SwitchFailed")
            return qsTr("Generation switch failed")
        if (applyController.status === "Applied")
            return qsTr("Applied")
        if (applyController.status === "Idle" || applyController.status === "Validating")
            return qsTr("Resolving…")
        return qsTr("Clean")
    }

    // Single premium surface: sidebar + content share one dark plane.
    Rectangle {
        id: appSurface
        anchors.fill: parent
        color: RyokuTheme.background

        // Window entrance (once): fade + scale, plus a subtle X tilt in the
        // Cinematic profile. Finite; transforms are identity afterwards.
        opacity: 0
        scale: RyokuTheme.motion_scale_from
        transform: Rotation {
            id: entranceTilt
            origin.x: appSurface.width / 2
            origin.y: appSurface.height / 2
            axis { x: 1; y: 0; z: 0 }
            angle: RyokuTheme.motion_tilt
        }

        ParallelAnimation {
            id: windowEnter
            running: true
            NumberAnimation {
                target: appSurface
                property: "opacity"
                to: 1
                duration: RyokuTheme.motion_emphasized
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_standard)
            }
            NumberAnimation {
                target: appSurface
                property: "scale"
                to: 1
                duration: RyokuTheme.motion_emphasized
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
            }
            NumberAnimation {
                target: entranceTilt
                property: "angle"
                to: 0
                duration: RyokuTheme.motion_emphasized
                easing.type: Easing.BezierSpline
                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
            }
        }

        // Soft Material You wash (static — no animated shader)
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.06)
                }
                GradientStop {
                    position: 0.45
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(RyokuTheme.secondary.r, RyokuTheme.secondary.g, RyokuTheme.secondary.b, 0.04)
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── Sidebar ───────────────────────────────────────────────────
            Rectangle {
                id: sidebar
                Layout.preferredWidth: RyokuTheme.sidebar_width
                Layout.fillHeight: true
                color: RyokuTheme.glass_surface

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: RyokuTheme.border_width
                    color: RyokuTheme.glass_border
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: RyokuTheme.spacing_md
                    spacing: RyokuTheme.spacing_xs

                    Text {
                        id: sidebarTitle
                        text: qsTr("Ryoku Settings")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_brand
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: qsTr("Desktop Experience")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                        Layout.fillWidth: true
                        Layout.bottomMargin: RyokuTheme.spacing_sm
                    }

                    RyokuSearchField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.bottomMargin: RyokuTheme.spacing_xs
                        onTextChanged: resultsList.currentIndex = 0
                        onMoveSelection: function(delta) { root.moveSearchSelection(delta) }
                        onSubmit: root.openSearchResult(root.searchResults[resultsList.currentIndex])
                        onEscapePressed: root.closeSearch()
                    }

                    // ── Search results (replace the nav list while searching) ──
                    ListView {
                        id: resultsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.searching && root.searchResults.length > 0
                        model: root.searchResults
                        clip: true
                        spacing: RyokuTheme.spacing_xxs
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false
                        delegate: Item {
                            id: resultRow
                            required property var modelData
                            required property int index
                            readonly property bool current: ListView.isCurrentItem
                            width: ListView.view.width
                            height: 48

                            Rectangle {
                                anchors.fill: parent
                                radius: RyokuTheme.radius_md
                                color: resultRow.current ? RyokuTheme.primary_tint_strong
                                     : (resultHover.hovered ? RyokuTheme.primary_tint : "transparent")
                                Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: RyokuTheme.spacing_sm
                                anchors.rightMargin: RyokuTheme.spacing_sm
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: resultRow.modelData.label
                                    color: resultRow.current ? RyokuTheme.primary : RyokuTheme.on_surface
                                    font.pixelSize: RyokuTheme.font_body
                                    font.bold: resultRow.modelData.isPage
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: resultRow.modelData.isPage ? qsTr("Page") : resultRow.modelData.pageTitle
                                    color: RyokuTheme.on_surface_muted
                                    font.pixelSize: RyokuTheme.font_caption
                                    elide: Text.ElideRight
                                }
                            }

                            HoverHandler { id: resultHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    resultsList.currentIndex = resultRow.index
                                    root.openSearchResult(resultRow.modelData)
                                }
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.searching && root.searchResults.length === 0
                        spacing: RyokuTheme.spacing_xxs
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: qsTr("No results for “%1”").arg(searchField.text.trim())
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: qsTr("Try a page name or an option label.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.searching
                        contentHeight: navColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Selected pill: one indicator that glides between items.
                        Rectangle {
                            id: navIndicator
                            readonly property Item target: navRepeater.count > root.currentIndex
                                                           ? navRepeater.itemAt(root.currentIndex) : null
                            width: navColumn.width
                            height: target ? target.height : 0
                            y: target ? target.y : 0
                            visible: target !== null
                            radius: RyokuTheme.radius_md
                            color: RyokuTheme.primary_tint_strong
                            border.width: RyokuTheme.border_width
                            border.color: Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.30)

                            Behavior on y {
                                NumberAnimation {
                                    duration: RyokuTheme.motion_standard
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
                                }
                            }

                            // Leading accent bar; restarts its grow on each selection.
                            Rectangle {
                                id: navAccent
                                width: 3
                                radius: 2
                                height: parent.height - RyokuTheme.spacing_sm
                                anchors.left: parent.left
                                anchors.leftMargin: RyokuTheme.spacing_xxs
                                anchors.verticalCenter: parent.verticalCenter
                                color: RyokuTheme.primary
                                transformOrigin: Item.Center
                            }

                            Connections {
                                target: root
                                function onCurrentIndexChanged() { accentGrow.restart() }
                            }

                            NumberAnimation {
                                id: accentGrow
                                target: navAccent
                                property: "scale"
                                from: 0.3
                                to: 1
                                duration: RyokuTheme.motion_emphasized
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
                            }
                        }

                        ColumnLayout {
                            id: navColumn
                            width: parent.width
                            spacing: RyokuTheme.spacing_xxs
                            Repeater {
                                id: navRepeater
                                model: root.pages
                                delegate: RyokuNavItem {
                                    required property var modelData
                                    required property int index
                                    title: modelData.title
                                    iconName: modelData.icon
                                    selected: root.currentIndex === index
                                    Layout.fillWidth: true
                                    onClicked: root.goToPage(index, 0)
                                }
                            }
                        }
                    }

                    RyokuBadge {
                        visible: paletteManager.usingFallback
                        text: qsTr("Fallback palette")
                        kind: "modified"
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Content ───────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: RyokuTheme.spacing_lg
                    spacing: RyokuTheme.spacing_md

                    RyokuApplyBanner {
                        Layout.fillWidth: true
                    }

                    // Pages stay instantiated (they hold drafts); StackLayout hides
                    // all but the current one, and only that page fades/slides in.
                    StackLayout {
                        id: pageStack
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: root.currentIndex
                        transform: Translate { id: pageShift }

                        HomePage { }
                        AppearancePage {
                            id: appearancePage
                            onDirtyChanged: {
                                root.appearanceDirty = dirty
                                applyController.unsavedDraft = root.appearanceDirty
                                                        || root.appsDirty
                                                        || root.displaysDirty
                            }
                            onErrorMessageChanged: root.appearanceError = errorMessage
                        }
                        NetworkPage { }
                        BluetoothPage { }
                        SoundPage { }
                        DisplaysPage {
                            id: displaysPage
                            onDirtyChanged: {
                                root.displaysDirty = dirty
                                applyController.unsavedDraft = root.appearanceDirty
                                                        || root.appsDirty
                                                        || root.displaysDirty
                            }
                            onErrorMessageChanged: root.displaysError = errorMessage
                        }
                        PowerPage { }
                        AppsPage {
                            id: appsPage
                            onDirtyChanged: {
                                root.appsDirty = dirty
                                applyController.unsavedDraft = root.appearanceDirty
                                                        || root.appsDirty
                                                        || root.displaysDirty
                            }
                            onErrorMessageChanged: root.appsError = errorMessage
                        }
                        SystemPage { }
                        NixUpdatesPage { }
                        AboutPage { }
                    }
                }
            }
        }
    }
}
