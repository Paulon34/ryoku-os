pragma Singleton
import QtQuick

/*
  Ryoku design tokens — Phase 8A visual foundation.

  paletteManager is injected from Main.qml (root context property).

  IMPORTANT — QML signal-handler naming:
    A property named `onSurface` alongside `surface` is treated as a broken /
    invalid color (#000000). Same for onPrimary, onBackground, etc.
    Use snake_case `on_*` tokens (Matugen key style) so they are NOT `on`+Capital.

  Naming:
    Canonical tokens use snake_case (spacing_md, radius_lg, glass_alpha).
    Legacy camelCase aliases were removed in 8E after migrating all consumers.
*/
QtObject {
    id: theme

    property var paletteManager: null

    readonly property bool hasManager: paletteManager !== null && paletteManager !== undefined

    // ── Material You dynamic colors (snake_case) ──────────────────────────
    readonly property color primary: hasManager ? paletteManager.primary : "#a8c8ff"
    readonly property color on_primary: hasManager ? paletteManager.onPrimary : "#00315f"
    readonly property color secondary: hasManager ? paletteManager.secondary : "#b8c8e0"
    readonly property color on_secondary: hasManager ? paletteManager.onSecondary : "#223148"
    readonly property color tertiary: hasManager ? paletteManager.tertiary : "#d3bfe6"
    readonly property color background: hasManager ? paletteManager.background : "#111318"
    readonly property color on_background: hasManager ? paletteManager.onBackground : "#e2e2e9"
    readonly property color surface: hasManager ? paletteManager.surface : "#111318"
    readonly property color on_surface: hasManager ? paletteManager.onSurface : "#e2e2e9"
    // surface_variant is a SURFACE token (dark) — never use as text.
    readonly property color surface_variant: hasManager ? paletteManager.surfaceVariant : "#43474e"
    readonly property color surface_container: hasManager ? paletteManager.surfaceContainer : "#1d2024"
    readonly property color surface_container_high: hasManager ? paletteManager.surfaceContainerHigh : "#282a2f"
    readonly property color outline: hasManager ? paletteManager.outline : "#8d9199"
    readonly property color error: hasManager ? paletteManager.error : "#ffb4ab"
    readonly property color on_error: hasManager ? paletteManager.onError : "#690005"

    // Secondary text: on_surface with opacity (legible on dark surfaces).
    readonly property color on_surface_muted: Qt.rgba(on_surface.r, on_surface.g, on_surface.b, 0.72)
    readonly property color on_background_muted: Qt.rgba(on_background.r, on_background.g, on_background.b, 0.72)

    // ── Glass language (controlled translucency — no heavy blur) ──────────
    readonly property real surface_alpha: 0.94
    readonly property real glass_alpha: 0.82
    readonly property real border_alpha: 0.28
    readonly property real highlight_alpha: 0.12
    readonly property real tint_alpha: 0.16
    readonly property real tint_strong_alpha: 0.28
    readonly property real shadow_opacity: 0.40
    readonly property int shadow_y: 5
    readonly property int shadow_spread: 2

    readonly property color glass_bg: Qt.rgba(background.r, background.g, background.b, surface_alpha)
    readonly property color glass_surface: Qt.rgba(surface_container.r, surface_container.g, surface_container.b, glass_alpha)
    readonly property color glass_surface_high: Qt.rgba(surface_container_high.r, surface_container_high.g, surface_container_high.b, glass_alpha)
    readonly property color glass_border: Qt.rgba(outline.r, outline.g, outline.b, border_alpha)
    readonly property color glass_highlight: Qt.rgba(on_surface.r, on_surface.g, on_surface.b, highlight_alpha)
    readonly property color primary_tint: Qt.rgba(primary.r, primary.g, primary.b, tint_alpha)
    readonly property color primary_tint_strong: Qt.rgba(primary.r, primary.g, primary.b, tint_strong_alpha)
    readonly property color error_tint: Qt.rgba(error.r, error.g, error.b, 0.18)
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.48)
    readonly property color shadow_color: Qt.rgba(0, 0, 0, shadow_opacity)

    // ── Spacing ───────────────────────────────────────────────────────────
    readonly property int spacing_xxs: 4
    readonly property int spacing_xs: 8
    readonly property int spacing_sm: 12
    readonly property int spacing_md: 16
    readonly property int spacing_lg: 24
    readonly property int spacing_xl: 32

    // ── Radius ────────────────────────────────────────────────────────────
    readonly property int radius_sm: 10
    readonly property int radius_md: 14
    readonly property int radius_lg: 18
    readonly property int radius_xl: 24
    readonly property int radius_pill: 999

    // ── Cards / surfaces (tonal, low elevation) ───────────────────────────
    readonly property color card_surface: Qt.rgba(surface_container.r, surface_container.g, surface_container.b, 0.88)
    readonly property color card_border: Qt.rgba(outline.r, outline.g, outline.b, 0.16)
    readonly property color card_border_hover: Qt.rgba(primary.r, primary.g, primary.b, 0.34)
    // Two cheap rectangles (ambient + key) instead of a blurred shadow.
    readonly property real elevation_ambient: profile_economy ? 0.10 : (profile_cinematic ? 0.16 : 0.12)
    readonly property real elevation_key: profile_economy ? 0.0 : (profile_cinematic ? 0.16 : 0.10)
    readonly property int elevation_key_y: profile_cinematic ? 6 : 4

    // ── Material state layers ─────────────────────────────────────────────
    readonly property real state_hover: 0.06
    readonly property real state_pressed: 0.10
    readonly property real state_focus: 0.10
    readonly property real state_dragged: 0.16

    // ── Typography ────────────────────────────────────────────────────────
    // Page → section (card title, primary) → group (bold body) → control.
    readonly property int font_title: 26
    readonly property int font_brand: 20
    readonly property int font_section: 16
    readonly property int font_card: 15
    readonly property int font_body: 14
    readonly property int font_secondary: 13
    readonly property int font_caption: 12
    readonly property int font_mono: 12
    readonly property int font_display: 28

    // ── Motion (finite only — never continuous idle loops) ────────────────
    readonly property int animation_fast: 140
    readonly property int animation_normal: 180
    readonly property int animation_slow: 280

    // Motion system for new transitions. Curves are Material 3 cubic-bezier
    // control points (x1, y1, x2, y2) — the same four numbers Hyprland's
    // `bezier = name, x1, y1, x2, y2` and CSS cubic-bezier() take, so DMS
    // popouts / visual profiles can reuse them. Use with
    //   easing.type: Easing.BezierSpline
    //   easing.bezierCurve: RyokuTheme.motion_curve(RyokuTheme.curve_emphasized_decelerate)
    //
    // Values follow the shell visual profile (appearance.visualProfile), set
    // from Main.qml; the same profile drives DMS (patches ryoku-visual-profile).
    property string visual_profile: "balanced"
    readonly property bool profile_economy: visual_profile === "economy"
    readonly property bool profile_cinematic: visual_profile === "cinematic"

    readonly property int motion_fast: profile_economy ? 90 : 120                         // state layers, bubbles
    readonly property int motion_standard: profile_economy ? 120 : (profile_cinematic ? 240 : 200) // page / panel enter
    readonly property int motion_emphasized: profile_economy ? 160 : (profile_cinematic ? 320 : 280) // highlights, window entrance
    readonly property int motion_exit: profile_economy ? 100 : (profile_cinematic ? 150 : 140)       // leaving: shorter than enter
    readonly property int motion_offset: profile_economy ? 0 : (profile_cinematic ? 16 : 12)         // px — shared-axis slide
    readonly property real motion_scale_from: profile_economy ? 1.0 : (profile_cinematic ? 0.97 : 0.985)
    readonly property real motion_tilt: profile_cinematic ? 3 : 0                                    // degrees, X axis, entrance only

    readonly property var curve_standard: [0.2, 0.0, 0.0, 1.0]
    readonly property var curve_emphasized_decelerate: [0.05, 0.7, 0.1, 1.0]
    readonly property var curve_emphasized_accelerate: [0.3, 0.0, 0.8, 0.15]

    // Qt's BezierSpline wants the end point appended to each segment.
    function motion_curve(c) {
        return [c[0], c[1], c[2], c[3], 1.0, 1.0]
    }

    // ── Control metrics ───────────────────────────────────────────────────
    readonly property int control_height: 36
    readonly property int nav_item_height: 40
    readonly property int badge_height: 26
    readonly property int border_width: 1
    readonly property int sidebar_width: 268
    readonly property real disabled_opacity: 0.45

    // ── Iconography (Material Symbols Rounded — loaded in main.cpp) ───────
    readonly property string icon_font_family: "Material Symbols Rounded"
    readonly property int icon_size_nav: 22
    readonly property int icon_size_md: 24
    readonly property int icon_size_lg: 48
}
