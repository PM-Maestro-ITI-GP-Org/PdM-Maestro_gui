import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import PdM.Shell

/*
 * The Maestro window: a bottom tab bar, and one page per app above it.
 *
 * This is the only ApplicationWindow in the merged process. Every app becomes
 * an Item that lives inside the StackLayout below, which is why the contract
 * asks each repo to split its ApplicationWindow off from its page content.
 */
ApplicationWindow {
    id: window

    width: 1280
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: qsTr("PdM Maestro")

    Material.theme: Theme.dark ? Material.Dark : Material.Light
    Material.accent: Theme.accent
    color: Theme.background

    /*
     * The navigation model of the whole shell, in tab order.
     *
     * In Phase 1 this moves into PdM.Core's AppRegistry, so an app declares its
     * own entry from its own repo instead of the shell hard-coding four of
     * them. Until then this array is the single place that knows what tabs
     * exist, and `module` records the URI each port is expected to claim.
     */
    readonly property var apps: [
        {
            title: qsTr("Data Collection"),
            glyph: "◉",
            module: "PdM.DataCollection",
            repo: "motor_recorder_gui",
            status: qsTr("Phase 2. The repo is checked out under apps/data_collection "
                       + "and still builds as a standalone app; it has not been split "
                       + "into a library and a page yet.")
        },
        {
            title: qsTr("ML / Ops"),
            glyph: "◆",
            module: "PdM.MlOps",
            repo: "pdm_mlops_gui (to be created)",
            status: qsTr("Phase 4. The ML/Ops pipeline exists but has no GUI yet, so "
                       + "this tab is written against the contract from the start "
                       + "rather than ported to it.")
        },
        {
            title: qsTr("OTA Update"),
            glyph: "↓",
            module: "PdM.Ota",
            repo: "ota_update_gui",
            status: qsTr("Phase 3. The repo is checked out under apps/ota and still "
                       + "builds as a standalone app; it has not been split into a "
                       + "library and a page yet.")
        },
        {
            title: qsTr("AI Agent"),
            glyph: "★",
            module: "PdM.Agent",
            repo: "pdm_agent_gui (to be created)",
            status: qsTr("Phase 5, lowest priority. The tab exists now so the "
                       + "four-tab layout is real and the slot is reserved.")
        }
    ]

    StackLayout {
        id: stack
        anchors.fill: parent
        currentIndex: tabBar.currentIndex

        Repeater {
            model: window.apps

            Loader {
                id: pageLoader

                required property int index
                required property var modelData

                /*
                 * Pages load on first visit and are then kept for the life of
                 * the window.
                 *
                 * The obvious binding -- active: index === stack.currentIndex --
                 * would also *unload* the page on the way out, destroying
                 * whatever the app was in the middle of: an in-progress
                 * recording, a half-finished OTA transfer, an open MQTT
                 * subscription. So `loaded` latches on and never clears. The
                 * cost is that a visited tab keeps its memory; the alternative
                 * loses work every time the user looks at another tab.
                 */
                property bool loaded: false
                active: loaded

                Component.onCompleted: if (index === stack.currentIndex) loaded = true

                Connections {
                    target: stack
                    function onCurrentIndexChanged() {
                        if (stack.currentIndex === pageLoader.index)
                            pageLoader.loaded = true
                    }
                }

                /* Swapped for the app's real page -- DataCollectionPage and
                   friends -- as each repo lands. */
                sourceComponent: Component {
                    PlaceholderPage {
                        title: pageLoader.modelData.title
                        glyph: pageLoader.modelData.glyph
                        moduleUri: pageLoader.modelData.module
                        repo: pageLoader.modelData.repo
                        status: pageLoader.modelData.status
                    }
                }
            }
        }
    }

    footer: Rectangle {
        implicitHeight: tabBar.implicitHeight
        color: Theme.surface

        /* The tab bar sits on a surface, so it needs its own top edge to
           separate it from a page painted in the background colour. */
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Theme.border
        }

        TabBar {
            id: tabBar
            anchors.fill: parent
            background: null

            /* Without this the window opens on the second tab. A TabBar whose
               buttons come from a Repeater does not reliably settle on index 0:
               the Container tracks the item being inserted, so the last
               insertion to complete wins. Assigning after construction rather
               than binding currentIndex leaves the user's own clicks alone. */
            Component.onCompleted: tabBar.setCurrentIndex(0)

            Repeater {
                model: window.apps

                TabButton {
                    id: tabButton

                    required property int index
                    required property var modelData

                    readonly property bool current: tabBar.currentIndex === index

                    padding: Theme.spacingTight
                    background: null

                    contentItem: ColumnLayout {
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tabButton.modelData.glyph
                            font.pixelSize: 20
                            color: tabButton.current ? Theme.accent : Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tabButton.modelData.title
                            font.pixelSize: Theme.fontSmall
                            font.weight: tabButton.current ? Font.DemiBold : Font.Normal
                            color: tabButton.current ? Theme.accent : Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }
        }
    }
}
