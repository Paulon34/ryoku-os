import QtQuick
import QtQuick.Layouts
import Ryoku.Settings

Flickable {
    id: root
    contentHeight: column.implicitHeight + RyokuTheme.spacing_lg
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    // --- Draft state (unchanged semantics) ---
    property string draftWallpaper: ""
    property string draftLoginWallpaper: ""
    property bool draftDynamicColors: true
    property bool draftAnimations: true
    property bool draftTransparencyNull: true
    property real draftTransparency: 0.0
    property bool dirty: false
    property bool justSaved: false
    property bool needsApply: false
    property string errorMessage: ""
    property string wallpaperPreviewNote: ""
    property bool choosingLoginWallpaper: false

    // Video wallpaper draft. draftWallpaper stays the static image either way.
    property string draftWallpaperType: "image"
    property string draftVideo: ""
    property bool draftVideoLoop: true
    property bool draftVideoAudio: false
    property string draftVideoProfile: "balanced"
    property bool draftVideoPauseCovered: true
    // Which gallery is shown — a view choice, not the active wallpaper.
    property string galleryMode: "image"
    readonly property bool videoActive: draftWallpaperType === "video" && draftVideo.length > 0
    readonly property var videoProfiles: [
        { id: "economy", label: qsTr("Economy") },
        { id: "balanced", label: qsTr("Balanced") },
        { id: "quality", label: qsTr("Quality") }
    ]

    function isUnset(v) {
        return v === null || v === undefined
    }

    function setVisualProfile(profile, autoMode) {
        if (!settingsStore.saveVisualProfile(profile, autoMode))
            errorMessage = settingsStore.lastWriteError.length
                           ? settingsStore.lastWriteError
                           : qsTr("Save failed")
    }

    // appearance.shellStyle is part of the Nix apply subset: written now, it
    // reaches the desktop on the next Apply.
    function setShellStyle(style) {
        if (!settingsStore.saveShellStyle(style)) {
            errorMessage = settingsStore.lastWriteError.length
                           ? settingsStore.lastWriteError
                           : qsTr("Save failed")
            return
        }
        applyController.refresh()
    }

    component ProfileTile: Item {
        id: tile
        property string title: ""
        property string description: ""
        property bool selected: false
        signal activated

        implicitHeight: tileColumn.implicitHeight + RyokuTheme.spacing_md * 2
        activeFocusOnTab: true

        Rectangle {
            id: tileBg
            anchors.fill: parent
            radius: RyokuTheme.radius_md
            color: tile.selected ? RyokuTheme.primary_tint_strong : RyokuTheme.surface_container_high
            border.width: tile.selected ? 2 : RyokuTheme.border_width
            border.color: tile.selected ? RyokuTheme.primary
                        : (tileHover.hovered ? RyokuTheme.card_border_hover : RyokuTheme.card_border)
            Behavior on color { ColorAnimation { duration: RyokuTheme.motion_fast } }
            Behavior on border.color { ColorAnimation { duration: RyokuTheme.motion_fast } }

            RyokuStateLayer {
                anchors.fill: parent
                tint: tile.selected ? RyokuTheme.primary : RyokuTheme.on_surface
                hovered: tileHover.hovered
                pressed: tileMouse.pressed
                focused: tile.activeFocus
            }
        }

        Column {
            id: tileColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: RyokuTheme.spacing_md
            spacing: RyokuTheme.spacing_xxs
            Text {
                width: parent.width - checkDot.width
                text: tile.title
                color: tile.selected ? RyokuTheme.primary : RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: tile.description
                wrapMode: Text.WordWrap
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }
        }

        Rectangle {
            id: checkDot
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: RyokuTheme.spacing_sm
            width: 20
            height: 20
            radius: 10
            color: RyokuTheme.primary
            scale: tile.selected ? 1 : 0
            Behavior on scale {
                NumberAnimation {
                    duration: RyokuTheme.motion_standard
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
                }
            }
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: RyokuTheme.on_primary
                font.pixelSize: 11
                font.bold: true
            }
        }

        HoverHandler { id: tileHover }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                tile.forceActiveFocus()
                tile.activated()
            }
        }
        Keys.onSpacePressed: tile.activated()
        Keys.onReturnPressed: tile.activated()
        Keys.onEnterPressed: tile.activated()
    }

    // Called by Main's search before highlighting a label that only exists in
    // a specific view of this page. View state only — never touches drafts.
    function revealSearchTarget(tag) {
        if (tag === "video")
            galleryMode = "video"
    }

    function seedFromStore() {
        const w = settingsStore.wallpaperValue
        draftWallpaper = (w === null || w === undefined || w === "") ? "" : String(w)

        const vw = settingsStore.videoWallpaperValue
        const video = (vw && typeof vw === "object") ? vw : ({})
        draftVideo = video.file ? String(video.file) : ""
        draftVideoLoop = isUnset(video.loop) ? true : Boolean(video.loop)
        draftVideoAudio = isUnset(video.audio) ? false : Boolean(video.audio)
        draftVideoProfile = ["economy", "balanced", "quality"].indexOf(video.profile) >= 0
                            ? video.profile : "balanced"
        draftVideoPauseCovered = isUnset(video.pauseWhenCovered) ? true : Boolean(video.pauseWhenCovered)
        draftWallpaperType = (settingsStore.wallpaperTypeValue === "video" && draftVideo.length)
                             ? "video" : "image"
        galleryMode = draftWallpaperType

        const lw = settingsStore.loginWallpaperValue
        draftLoginWallpaper = (lw === null || lw === undefined || lw === "") ? "" : String(lw)

        const dc = settingsStore.dynamicColorsValue
        draftDynamicColors = (dc === null || dc === undefined) ? true : Boolean(dc)

        const an = settingsStore.animationsValue
        draftAnimations = (an === null || an === undefined) ? true : Boolean(an)

        const tr = settingsStore.transparencyValue
        if (tr === null || tr === undefined) {
            draftTransparencyNull = true
            draftTransparency = 0.0
        } else {
            draftTransparencyNull = false
            draftTransparency = Number(tr)
        }

        dirty = false
        errorMessage = ""
        wallpaperPreviewNote = ""
        choosingLoginWallpaper = false
    }

    function markDirty() {
        dirty = true
        justSaved = false
        needsApply = false
        errorMessage = ""
    }

    readonly property string statusLabel: {
        if (errorMessage.length > 0)
            return qsTr("Error")
        if (justSaved && needsApply)
            return qsTr("Needs Apply")
        if (justSaved)
            return qsTr("Saved")
        if (dirty)
            return qsTr("Unsaved changes")
        return qsTr("Clean")
    }

    readonly property string statusKind: {
        if (errorMessage.length > 0)
            return "error"
        if (justSaved && needsApply)
            return "needs_apply"
        if (justSaved)
            return "applied"
        if (dirty)
            return "modified"
        return "neutral"
    }

    readonly property string transparencyLabel: root.draftTransparencyNull
        ? qsTr("Current system value")
        : qsTr("%1%").arg(Math.round(root.draftTransparency * 100))

    function selectWallpaper(fileName) {
        errorMessage = ""
        wallpaperPreviewNote = ""
        if (!wallpaperApplier.applyWallpaper(fileName)) {
            errorMessage = wallpaperApplier.lastError.length
                           ? wallpaperApplier.lastError
                           : qsTr("Failed to apply wallpaper")
            return
        }
        draftWallpaper = fileName
        draftWallpaperType = "image"
        markDirty()
        wallpaperPreviewNote = qsTr("Wallpaper preview remains active until changed again.")
    }

    function applyVideo(fileName) {
        return wallpaperApplier.applyVideoWallpaper(fileName, draftVideoLoop, draftVideoAudio,
                                                    draftVideoProfile, draftVideoPauseCovered)
    }

    function selectVideoWallpaper(fileName) {
        errorMessage = ""
        wallpaperPreviewNote = ""
        if (!applyVideo(fileName)) {
            errorMessage = wallpaperApplier.lastError.length
                           ? wallpaperApplier.lastError
                           : qsTr("Failed to apply video wallpaper")
            return
        }
        draftVideo = fileName
        draftWallpaperType = "video"
        markDirty()
        wallpaperPreviewNote = qsTr("Wallpaper preview remains active until changed again.")
    }

    // Options are live like the wallpaper itself when a video is playing.
    function videoOptionChanged() {
        markDirty()
        if (!videoActive)
            return
        if (!applyVideo(draftVideo))
            errorMessage = wallpaperApplier.lastError.length
                           ? wallpaperApplier.lastError
                           : qsTr("Failed to apply video wallpaper")
    }

    Connections {
        target: wallpaperApplier
        function onVideoApplyFinished(ok) {
            if (!ok)
                root.errorMessage = wallpaperApplier.lastError.length
                                    ? wallpaperApplier.lastError
                                    : qsTr("Failed to apply video wallpaper")
        }
    }

    function selectLoginWallpaper(fileName) {
        errorMessage = ""
        draftLoginWallpaper = fileName
        choosingLoginWallpaper = false
        markDirty()
    }

    function useCurrentAsLoginWallpaper() {
        if (!draftWallpaper.length || videoActive) {
            errorMessage = qsTr("Select a desktop wallpaper first.")
            return
        }
        errorMessage = ""
        draftLoginWallpaper = draftWallpaper
        choosingLoginWallpaper = false
        markDirty()
    }

    function resetDraft() {
        seedFromStore()
        justSaved = false
        needsApply = false
        if (wallpaperPreviewNote.length)
            wallpaperPreviewNote = qsTr("Wallpaper preview remains active until changed again.")
    }

    function saveDraft() {
        errorMessage = ""
        const wallpaperVar = draftWallpaper.length ? draftWallpaper : null
        const loginWallpaperVar = draftLoginWallpaper.length ? draftLoginWallpaper : null
        const transparencyVar = draftTransparencyNull ? null : draftTransparency

        // Image-only files gain no video keys; an explicit null (= default) stays null.
        const storedType = settingsStore.wallpaperTypeValue
        const typeVar = draftWallpaperType === "video" ? "video" : (isUnset(storedType) ? null : "image")
        const storedVideo = settingsStore.videoWallpaperValue
        const stored = (storedVideo && typeof storedVideo === "object") ? storedVideo : ({})
        const keepNull = function(key, draft, fallback) {
            return (stored[key] === null && draft === fallback) ? null : draft
        }
        const videoVar = (draftVideo.length || !isUnset(storedVideo)) ? {
            file: draftVideo.length ? draftVideo : null,
            loop: keepNull("loop", draftVideoLoop, true),
            audio: keepNull("audio", draftVideoAudio, false),
            profile: keepNull("profile", draftVideoProfile, "balanced"),
            pauseWhenCovered: keepNull("pauseWhenCovered", draftVideoPauseCovered, true)
        } : null

        if (!settingsStore.saveAppearanceWithVideo(wallpaperVar, loginWallpaperVar, draftDynamicColors,
                                                   draftAnimations, transparencyVar, typeVar, videoVar)) {
            errorMessage = settingsStore.lastWriteError.length
                           ? settingsStore.lastWriteError
                           : qsTr("Save failed")
            return
        }

        dirty = false
        justSaved = true
        needsApply = false
        wallpaperPreviewNote = ""
        choosingLoginWallpaper = false
        gitStatus.refresh()
        applyController.refresh()
    }

    Connections {
        target: applyController
        function onChanged() {
            if (root.dirty || !root.justSaved)
                return
            const s = applyController.status
            root.needsApply = (s === "NeedsApply" || s === "Ready"
                               || s === "ValidationFailed" || s === "ApplyFailed"
                               || s === "AuthorizationDenied" || s === "AuthorizationError")
        }
    }

    Component.onCompleted: seedFromStore()

    component VideoOptionRow: RowLayout {
        id: optionRow
        property string title: ""
        property string caption: ""
        property bool checked: false
        signal toggled(bool value)
        spacing: RyokuTheme.spacing_sm

        Column {
            Layout.fillWidth: true
            spacing: RyokuTheme.spacing_xxs
            Text {
                width: parent.width
                text: optionRow.title
                color: RyokuTheme.on_surface
                font.pixelSize: RyokuTheme.font_body
                font.bold: true
            }
            Text {
                width: parent.width
                visible: optionRow.caption.length > 0
                wrapMode: Text.WordWrap
                text: optionRow.caption
                color: RyokuTheme.on_surface_muted
                font.pixelSize: RyokuTheme.font_caption
            }
        }
        RyokuToggle {
            checked: optionRow.checked
            enabled: !wallpaperApplier.busy
            onToggled: function(v) { optionRow.toggled(v) }
        }
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

        // ── Page header ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: RyokuTheme.spacing_sm
            Text {
                text: qsTr("Appearance")
                color: RyokuTheme.on_background
                font.pixelSize: RyokuTheme.font_title
                font.bold: true
                Layout.fillWidth: true
            }
            RyokuBadge {
                text: root.statusLabel
                kind: root.statusKind
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

        // ── Wallpaper ─────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Wallpaper")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                // Image | Video
                Row {
                    spacing: RyokuTheme.spacing_xs
                    RyokuButton {
                        text: qsTr("Image")
                        variant: root.galleryMode === "image" ? "tonal" : "ghost"
                        onClicked: root.galleryMode = "image"
                    }
                    RyokuButton {
                        text: qsTr("Video")
                        variant: root.galleryMode === "video" ? "tonal" : "ghost"
                        onClicked: root.galleryMode = "video"
                    }
                }

                // Hero preview — videos show their poster frame (no playback here).
                Item {
                    id: hero
                    width: parent.width
                    height: Math.round(Math.min(220, Math.max(168, width * 0.32)))

                    readonly property string name: root.videoActive ? root.draftVideo : root.draftWallpaper
                    readonly property url source: {
                        if (root.videoActive) {
                            const _ = videoWallpaperGallery.posterRevision
                            return videoWallpaperGallery.posterUrlForId(root.draftVideo)
                        }
                        return root.draftWallpaper.length ? wallpaperGallery.urlForId(root.draftWallpaper) : ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: RyokuTheme.shadow_y
                        radius: RyokuTheme.radius_lg
                        color: RyokuTheme.shadow_color
                        opacity: 0.45
                    }

                    Rectangle {
                        id: heroFrame
                        anchors.fill: parent
                        radius: RyokuTheme.radius_lg
                        color: RyokuTheme.glass_surface_high
                        border.width: RyokuTheme.border_width
                        border.color: RyokuTheme.glass_border
                        clip: true

                        Image {
                            id: heroImage
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 960
                            sourceSize.height: 540
                            visible: hero.name.length > 0
                            source: hero.source
                        }

                        // Video poster still being generated
                        Text {
                            anchors.centerIn: parent
                            visible: root.videoActive && heroImage.status !== Image.Ready
                            text: "▶"
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_title * 2
                        }

                        // Empty state
                        Column {
                            anchors.centerIn: parent
                            spacing: RyokuTheme.spacing_xxs
                            visible: hero.name.length === 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("No wallpaper selected")
                                color: RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_body
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("Current system wallpaper")
                                color: RyokuTheme.on_surface_muted
                                font.pixelSize: RyokuTheme.font_caption
                            }
                        }

                        // Bottom glass overlay (no blur)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 52
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                }
                            }
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: RyokuTheme.spacing_sm
                            spacing: RyokuTheme.spacing_sm

                            Text {
                                Layout.fillWidth: true
                                text: hero.name.length
                                      ? hero.name
                                      : qsTr("System default")
                                color: RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_body
                                font.bold: true
                                elide: Text.ElideMiddle
                            }

                            RyokuBadge {
                                visible: root.videoActive
                                text: "▶ " + qsTr("Video")
                                kind: "neutral"
                            }

                            RyokuBadge {
                                text: hero.name.length
                                      ? qsTr("Selected")
                                      : qsTr("Current")
                                kind: hero.name.length ? "current" : "neutral"
                            }
                        }

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

                Text {
                    width: parent.width
                    visible: root.wallpaperPreviewNote.length > 0
                    wrapMode: Text.WordWrap
                    text: root.wallpaperPreviewNote
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Text {
                    width: parent.width
                    text: qsTr("Gallery")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_secondary
                    font.bold: true
                }

                // Responsive gallery — columns from available width
                GridView {
                    id: gallery
                    width: parent.width
                    readonly property int minCell: 92
                    readonly property int maxCell: 120
                    readonly property int cols: Math.max(2, Math.floor(width / minCell))
                    readonly property int cell: Math.min(maxCell, Math.floor(width / cols))
                    readonly property var source: root.galleryMode === "video"
                                                  ? videoWallpaperGallery : wallpaperGallery
                    cellWidth: cell
                    cellHeight: cell
                    height: {
                        if (source.count === 0)
                            return 0
                        const rows = Math.ceil(source.count / Math.max(1, cols))
                        return rows * cell
                    }
                    interactive: false
                    clip: true
                    model: source
                    delegate: Item {
                        width: gallery.cellWidth
                        height: gallery.cellHeight
                        required property string fileName
                        required property url url
                        required property bool isVideo
                        required property url posterUrl

                        readonly property bool selected: isVideo
                                                         ? (root.videoActive && root.draftVideo === fileName)
                                                         : (!root.videoActive && root.draftWallpaper === fileName)

                        Rectangle {
                            id: thumb
                            anchors.fill: parent
                            anchors.margins: RyokuTheme.spacing_xxs
                            radius: RyokuTheme.radius_md
                            color: RyokuTheme.glass_surface_high
                            border.width: selected ? 2 : RyokuTheme.border_width
                            border.color: selected
                                          ? RyokuTheme.primary
                                          : (thumbHover.hovered
                                             ? Qt.rgba(RyokuTheme.primary.r, RyokuTheme.primary.g, RyokuTheme.primary.b, 0.45)
                                             : RyokuTheme.glass_border)
                            clip: true

                            Behavior on border.color {
                                ColorAnimation { duration: RyokuTheme.animation_fast }
                            }

                            Image {
                                anchors.fill: parent
                                source: isVideo ? posterUrl : url
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 160
                                sourceSize.height: 160
                                opacity: thumbHover.hovered || selected ? 1.0 : 0.92
                                Behavior on opacity {
                                    NumberAnimation { duration: RyokuTheme.animation_fast }
                                }
                            }

                            // Video badge — poster thumbnails look like images otherwise
                            Rectangle {
                                visible: isVideo
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: 22
                                height: 22
                                radius: 11
                                color: Qt.rgba(0, 0, 0, 0.55)
                                Text {
                                    anchors.centerIn: parent
                                    text: "▶"
                                    color: "white"
                                    font.pixelSize: RyokuTheme.font_caption
                                }
                            }

                            // Selection check — meaning beyond color alone
                            Rectangle {
                                visible: selected
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6
                                width: 22
                                height: 22
                                radius: 11
                                color: RyokuTheme.primary
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: RyokuTheme.on_primary
                                    font.pixelSize: RyokuTheme.font_caption
                                    font.bold: true
                                }
                            }

                            HoverHandler { id: thumbHover }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !wallpaperApplier.busy
                                cursorShape: wallpaperApplier.busy ? Qt.BusyCursor : Qt.PointingHandCursor
                                onClicked: isVideo ? root.selectVideoWallpaper(fileName)
                                                   : root.selectWallpaper(fileName)
                            }
                        }
                    }
                }

                Text {
                    visible: gallery.source.count === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.galleryMode === "video"
                          ? qsTr("No video wallpapers found in %1. Add .mp4, .webm, .mkv or .mov files to assets/wallpapers.")
                            .arg(videoWallpaperGallery.galleryPath)
                          : qsTr("No wallpapers found in %1").arg(wallpaperGallery.galleryPath)
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                // ── Video options ─────────────────────────────────────────
                Column {
                    width: parent.width
                    visible: root.galleryMode === "video"
                    spacing: RyokuTheme.spacing_md
                    topPadding: RyokuTheme.spacing_xs

                    Column {
                        width: parent.width
                        spacing: RyokuTheme.spacing_xxs
                        Text {
                            width: parent.width
                            text: qsTr("Video wallpaper")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_secondary
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: wallpaperApplier.busy
                                  ? qsTr("Applying video wallpaper…")
                                  : qsTr("Hardware-decoded. Material You and the lock screen use a still frame of the video.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }

                    VideoOptionRow {
                        width: parent.width
                        title: qsTr("Loop")
                        checked: root.draftVideoLoop
                        onToggled: function(v) {
                            root.draftVideoLoop = v
                            root.videoOptionChanged()
                        }
                    }

                    VideoOptionRow {
                        width: parent.width
                        title: qsTr("Audio")
                        caption: qsTr("Off by default — wallpapers stay silent.")
                        checked: root.draftVideoAudio
                        onToggled: function(v) {
                            root.draftVideoAudio = v
                            root.videoOptionChanged()
                        }
                    }

                    VideoOptionRow {
                        width: parent.width
                        title: qsTr("Pause when covered")
                        caption: qsTr("Pauses while a fullscreen window or the lock screen hides the desktop.")
                        checked: root.draftVideoPauseCovered
                        onToggled: function(v) {
                            root.draftVideoPauseCovered = v
                            root.videoOptionChanged()
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: RyokuTheme.spacing_xs
                        Text {
                            width: parent.width
                            text: qsTr("Performance")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: qsTr("Economy ≈ 15 fps · Balanced ≈ 30 fps · Quality = original frame rate.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                        RyokuComboBox {
                            id: profileCombo
                            width: Math.min(parent.width, 320)
                            enabled: !wallpaperApplier.busy
                            model: root.videoProfiles
                            currentIndex: {
                                for (let i = 0; i < root.videoProfiles.length; ++i) {
                                    if (root.videoProfiles[i].id === root.draftVideoProfile)
                                        return i
                                }
                                return 1
                            }
                            onActivated: function(index) {
                                const id = root.videoProfiles[index].id
                                if (id === root.draftVideoProfile)
                                    return
                                root.draftVideoProfile = id
                                root.videoOptionChanged()
                            }
                        }
                    }
                }
            }
        }

        // ── Login screen (SDDM) ───────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Login screen")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Login screen wallpaper")
                    color: RyokuTheme.on_surface
                    font.pixelSize: RyokuTheme.font_body
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Choose the image used by SDDM before the session starts.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Item {
                    width: parent.width
                    height: Math.round(Math.min(160, Math.max(120, width * 0.28)))

                    Rectangle {
                        anchors.fill: parent
                        radius: RyokuTheme.radius_lg
                        color: RyokuTheme.glass_surface_high
                        border.width: RyokuTheme.border_width
                        border.color: RyokuTheme.glass_border
                        clip: true

                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 640
                            sourceSize.height: 360
                            visible: root.draftLoginWallpaper.length > 0
                            source: root.draftLoginWallpaper.length
                                    ? wallpaperGallery.urlForId(root.draftLoginWallpaper)
                                    : ""
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: RyokuTheme.spacing_xxs
                            visible: root.draftLoginWallpaper.length === 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("Theme default")
                                color: RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_body
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("SDDM embedded background")
                                color: RyokuTheme.on_surface_muted
                                font.pixelSize: RyokuTheme.font_caption
                            }
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: RyokuTheme.spacing_sm
                            spacing: RyokuTheme.spacing_sm

                            Text {
                                Layout.fillWidth: true
                                text: root.draftLoginWallpaper.length
                                      ? root.draftLoginWallpaper
                                      : qsTr("System default")
                                color: RyokuTheme.on_surface
                                font.pixelSize: RyokuTheme.font_body
                                font.bold: true
                                elide: Text.ElideMiddle
                            }

                            RyokuBadge {
                                text: root.draftLoginWallpaper.length
                                      ? qsTr("Selected")
                                      : qsTr("Current")
                                kind: root.draftLoginWallpaper.length ? "current" : "neutral"
                            }
                        }
                    }
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Use current wallpaper")
                        variant: "tonal"
                        enabled: root.draftWallpaper.length > 0 && !root.videoActive
                        onClicked: root.useCurrentAsLoginWallpaper()
                    }
                    RyokuButton {
                        text: root.choosingLoginWallpaper ? qsTr("Cancel") : qsTr("Choose")
                        variant: "ghost"
                        onClicked: root.choosingLoginWallpaper = !root.choosingLoginWallpaper
                    }
                    RyokuButton {
                        text: qsTr("Clear")
                        variant: "ghost"
                        visible: root.draftLoginWallpaper.length > 0
                        onClicked: {
                            root.draftLoginWallpaper = ""
                            root.choosingLoginWallpaper = false
                            root.markDirty()
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.videoActive
                    wrapMode: Text.WordWrap
                    text: qsTr("The login screen stays static — choose an image for it.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Text {
                    width: parent.width
                    visible: root.choosingLoginWallpaper
                    wrapMode: Text.WordWrap
                    text: qsTr("Pick a gallery image for the login screen. This is independent of the desktop wallpaper.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                GridView {
                    id: loginGallery
                    width: parent.width
                    visible: root.choosingLoginWallpaper
                    readonly property int minCell: 92
                    readonly property int maxCell: 120
                    readonly property int cols: Math.max(2, Math.floor(width / minCell))
                    readonly property int cell: Math.min(maxCell, Math.floor(width / cols))
                    cellWidth: cell
                    cellHeight: cell
                    height: {
                        if (!visible || wallpaperGallery.count === 0)
                            return 0
                        const rows = Math.ceil(wallpaperGallery.count / Math.max(1, cols))
                        return rows * cell
                    }
                    interactive: false
                    clip: true
                    model: wallpaperGallery
                    delegate: Item {
                        width: loginGallery.cellWidth
                        height: loginGallery.cellHeight
                        required property string fileName
                        required property url url
                        readonly property bool selected: root.draftLoginWallpaper === fileName

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: RyokuTheme.spacing_xxs
                            radius: RyokuTheme.radius_md
                            color: RyokuTheme.glass_surface_high
                            border.width: selected ? 2 : RyokuTheme.border_width
                            border.color: selected ? RyokuTheme.primary : RyokuTheme.glass_border
                            clip: true

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 160
                                sourceSize.height: 160
                                source: url
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectLoginWallpaper(fileName)
                            }
                        }
                    }
                }
            }
        }

        // ── Material You ──────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Material You")

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
                            text: qsTr("Dynamic colors")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: root.videoActive
                                  ? qsTr("Generated once from a still frame of the video wallpaper.")
                                  : qsTr("Use the current wallpaper to generate the Ryoku palette.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                    RyokuToggle {
                        checked: root.draftDynamicColors
                        onToggled: function(v) {
                            root.draftDynamicColors = v
                            root.markDirty()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs
                    Text {
                        text: qsTr("Live palette")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    Row {
                        spacing: RyokuTheme.spacing_xs
                        Repeater {
                            model: [
                                { label: qsTr("Primary"), color: RyokuTheme.primary },
                                { label: qsTr("Secondary"), color: RyokuTheme.secondary },
                                { label: qsTr("Tertiary"), color: RyokuTheme.tertiary },
                                { label: qsTr("Surface"), color: RyokuTheme.surface },
                                { label: qsTr("Container"), color: RyokuTheme.surface_container }
                            ]
                            delegate: Column {
                                required property var modelData
                                spacing: RyokuTheme.spacing_xxs
                                width: 56
                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: RyokuTheme.radius_sm
                                    color: modelData.color
                                    border.width: RyokuTheme.border_width
                                    border.color: RyokuTheme.glass_border
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    color: RyokuTheme.on_surface_muted
                                    font.pixelSize: RyokuTheme.font_caption
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: paletteManager.usingFallback
                        wrapMode: Text.WordWrap
                        text: qsTr("Fallback palette — Matugen colors unavailable.")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                }
            }
        }

        // ── Shell style (written immediately, applied by Nix) ─────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Shell style")

            Column {
                id: styleColumn
                width: parent.width
                spacing: RyokuTheme.spacing_md

                readonly property string current: settingsStore.shellStyleValue === "islands" ? "islands" : "quattro"

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Saved immediately; the desktop changes after Apply.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Row {
                    id: styleRow
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    readonly property real tileWidth: (width - spacing) / 2
                    readonly property real tileHeight: {
                        let h = 0
                        for (let i = 0; i < styleRepeater.count; ++i) {
                            const it = styleRepeater.itemAt(i)
                            if (it)
                                h = Math.max(h, it.implicitHeight)
                        }
                        return h
                    }

                    Repeater {
                        id: styleRepeater
                        model: [
                            { id: "quattro", title: qsTr("Quattro"),
                              text: qsTr("Flat top bar with workspace numbers, framed panels that grow from their icon, instant launcher. Inspired by Omarchy Quattro.") },
                            { id: "islands", title: qsTr("Islands"),
                              text: qsTr("Floating pill bar and soft glass panels of earlier Ryoku.") }
                        ]
                        delegate: ProfileTile {
                            required property var modelData
                            width: styleRow.tileWidth
                            height: Math.max(implicitHeight, styleRow.tileHeight)
                            title: modelData.title
                            description: modelData.text
                            selected: styleColumn.current === modelData.id
                            onActivated: if (!selected)
                                root.setShellStyle(modelData.id)
                        }
                    }
                }
            }
        }

        // ── Visual effects (live — written immediately, read by DMS) ──────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Visual effects")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_md

                readonly property string current: {
                    const p = settingsStore.visualProfileValue
                    return (p === "economy" || p === "cinematic") ? p : "balanced"
                }
                readonly property bool autoOn: settingsStore.visualProfileAutoValue === true
                id: effectsColumn

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Applied to the shell immediately — not part of Save Changes.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Row {
                    id: profileRow
                    width: parent.width
                    spacing: RyokuTheme.spacing_sm
                    readonly property real tileWidth: (width - spacing * 2) / 3
                    readonly property real tileHeight: {
                        let h = 0
                        for (let i = 0; i < profileRepeater.count; ++i) {
                            const it = profileRepeater.itemAt(i)
                            if (it)
                                h = Math.max(h, it.implicitHeight)
                        }
                        return h
                    }

                    Repeater {
                        id: profileRepeater
                        model: [
                            { id: "economy", title: qsTr("Economy"),
                              text: qsTr("Fades only, no blur or shadows. Longest battery life.") },
                            { id: "balanced", title: qsTr("Balanced"),
                              text: qsTr("Smooth motion and moderate blur. Recommended.") },
                            { id: "cinematic", title: qsTr("Cinematic"),
                              text: qsTr("Depth, stronger blur and elevation. Blur stays capped over video wallpapers.") }
                        ]
                        delegate: ProfileTile {
                            required property var modelData
                            width: profileRow.tileWidth
                            height: Math.max(implicitHeight, profileRow.tileHeight)
                            title: modelData.title
                            description: modelData.text
                            selected: effectsColumn.current === modelData.id
                            onActivated: root.setVisualProfile(modelData.id, effectsColumn.autoOn)
                        }
                    }
                }

                VideoOptionRow {
                    width: parent.width
                    title: qsTr("Automatic on battery")
                    caption: qsTr("Power saver or battery at 20% or less switches to Economy; on battery, Cinematic becomes Balanced.")
                    checked: effectsColumn.autoOn
                    onToggled: function(v) { root.setVisualProfile(effectsColumn.current, v) }
                }
            }
        }

        // ── Interface ─────────────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Interface")

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
                            text: qsTr("Animations")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: qsTr("Smooth interface transitions and motion.")
                            color: RyokuTheme.on_surface_muted
                            font.pixelSize: RyokuTheme.font_caption
                        }
                    }
                    RyokuToggle {
                        checked: root.draftAnimations
                        onToggled: function(v) {
                            root.draftAnimations = v
                            root.markDirty()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: RyokuTheme.spacing_xs

                    Text {
                        width: parent.width
                        text: qsTr("Language")
                        color: RyokuTheme.on_surface
                        font.pixelSize: RyokuTheme.font_body
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: qsTr("Applied immediately — not part of Save Changes.")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }
                    RyokuComboBox {
                        id: languageCombo
                        width: Math.min(parent.width, 320)
                        readonly property string langBump: languageManager.language
                        model: {
                            const _ = languageCombo.langBump
                            return languageManager.languageOptions()
                        }
                        currentIndex: {
                            const _ = languageCombo.langBump
                            const opts = languageManager.languageOptions()
                            for (let i = 0; i < opts.length; ++i) {
                                if (opts[i].id === languageManager.language)
                                    return i
                            }
                            return 0
                        }
                        onActivated: function(index) {
                            const opts = languageCombo.model
                            if (!opts || index < 0 || index >= opts.length)
                                return
                            const id = opts[index].id
                            if (id && id !== languageManager.language)
                                languageManager.language = id
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
                            text: qsTr("Transparency")
                            color: RyokuTheme.on_surface
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: true
                        }
                        Text {
                            text: root.transparencyLabel
                            color: root.draftTransparencyNull
                                   ? RyokuTheme.on_surface_muted
                                   : RyokuTheme.primary
                            font.pixelSize: RyokuTheme.font_body
                            font.bold: !root.draftTransparencyNull
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: qsTr("Glass strength for Ryoku surfaces. Saved to settings; shell projection comes later.")
                        color: RyokuTheme.on_surface_muted
                        font.pixelSize: RyokuTheme.font_caption
                    }

                    RyokuSlider {
                        width: parent.width
                        from: 0
                        to: 1
                        value: root.draftTransparency
                        enabled: !root.draftTransparencyNull
                        formatValue: function(v) { return qsTr("%1%").arg(Math.round(v * 100)) }
                        onMoved: function(v) {
                            root.draftTransparency = v
                            root.markDirty()
                        }
                    }

                    Row {
                        spacing: RyokuTheme.spacing_sm
                        RyokuButton {
                            text: qsTr("Set override")
                            variant: "tonal"
                            visible: root.draftTransparencyNull
                            onClicked: {
                                root.draftTransparencyNull = false
                                root.draftTransparency = 0.0
                                root.markDirty()
                            }
                        }
                        RyokuButton {
                            text: qsTr("Use system default")
                            variant: "ghost"
                            visible: !root.draftTransparencyNull
                            onClicked: {
                                root.draftTransparencyNull = true
                                root.draftTransparency = 0.0
                                root.markDirty()
                            }
                        }
                    }
                }
            }
        }

        // ── Future / read-only ────────────────────────────────────────────
        RyokuCard {
            Layout.fillWidth: true
            title: qsTr("Themes & fonts")

            Column {
                width: parent.width
                spacing: RyokuTheme.spacing_sm
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Read-only for now — editable in a later phase.")
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }
                RyokuSettingRow { label: qsTr("Icons"); value: settingsStore.iconTheme }
                RyokuSettingRow { label: qsTr("Cursor"); value: settingsStore.cursorTheme }
                RyokuSettingRow { label: qsTr("UI Font"); value: settingsStore.fontUi }
                RyokuSettingRow { label: qsTr("Mono Font"); value: settingsStore.fontMono }
            }
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
                          ? qsTr("You have unsaved appearance changes.")
                          : (root.justSaved && root.needsApply
                             ? qsTr("Appearance saved. Login wallpaper needs Apply to update SDDM.")
                             : (root.justSaved
                                ? qsTr("Appearance saved to settings.json.")
                                : qsTr("No pending appearance edits.")))
                    color: RyokuTheme.on_surface_muted
                    font.pixelSize: RyokuTheme.font_caption
                }

                Row {
                    spacing: RyokuTheme.spacing_sm
                    RyokuButton {
                        text: qsTr("Reset Changes")
                        variant: "ghost"
                        enabled: root.dirty || root.justSaved
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
    }
}
