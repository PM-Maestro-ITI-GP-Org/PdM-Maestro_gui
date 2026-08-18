/*
 * `pragma Singleton` pairs with QT_QML_SINGLETON_TYPE in CMakeLists.txt. Both
 * or neither -- a file that declares the pragma while the generated qmldir does
 * not (or the reverse) fails to load, and takes everything importing it down
 * with it.
 */
pragma Singleton
import QtQuick

/*
 * The palette, deliberately identical to motor_recorder_gui's Theme.qml.
 *
 * This is the seed of PdM.Core's Theme, not a second palette to maintain. In
 * Phase 1 this file moves into the pdm-core submodule and the copy in the data
 * collection repo is deleted, so both the shell and every tab resolve colour
 * through one object. Starting from the app's existing values rather than a
 * fresh set means that move is a deletion, not a redesign -- and the shell
 * looks like the same product as the tab inside it on day one.
 *
 * Note the hex order: Qt reads 8-digit literals as #AARRGGBB, alpha FIRST.
 * Writing them the CSS way (#RRGGBBAA) compiles fine and renders the wrong
 * colour at the wrong transparency.
 */
QtObject {
    property bool dark: false

    /* ---- surfaces ---- */
    readonly property color background:  dark ? "#12141c" : "#f6f7fb"
    readonly property color surface:     dark ? "#1b1e29" : "#ffffff"
    readonly property color surfaceAlt:  dark ? "#232735" : "#f0f2f8"
    readonly property color border:      dark ? "#2f3444" : "#e2e6ef"

    /* ---- text ---- */
    readonly property color textPrimary:   dark ? "#eef1f7" : "#161a23"
    readonly property color textSecondary: dark ? "#9aa3b6" : "#5b6478"
    readonly property color textDisabled:  dark ? "#5d6577" : "#a2aab9"

    /* ---- accents ---- */
    readonly property color accent:      "#2f6df6"
    readonly property color accentHover: "#2559d6"
    readonly property color accentSoft:  dark ? "#1d2b4d" : "#e7efff"

    readonly property color success:     "#1a9d5a"
    readonly property color successSoft: dark ? "#12301f" : "#e3f6ea"
    readonly property color warning:     "#c77700"
    readonly property color warningSoft: dark ? "#33260c" : "#fdf1de"
    readonly property color danger:      "#d13b3b"
    readonly property color dangerSoft:  dark ? "#3a1a1a" : "#fce9e9"

    readonly property color recording:     "#e0245e"
    readonly property color recordingSoft: dark ? "#3d1424" : "#fde8ef"

    /* ---- type ---- */
    readonly property int fontTiny:    12
    readonly property int fontSmall:   14
    readonly property int fontBody:    16
    readonly property int fontTitle:   20
    readonly property int fontDisplay: 28
    readonly property string monoFamily: "DejaVu Sans Mono"

    /* ---- spacing ---- */
    readonly property int spacingTight: 8
    readonly property int spacing:      16
    readonly property int spacingWide:  24
    readonly property int radius:       12
    readonly property int radiusSmall:  8
}
