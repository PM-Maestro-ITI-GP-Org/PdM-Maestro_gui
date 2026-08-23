import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import PdM.Core
import PdM.Shell

/*
 * The Maestro window: a bottom tab bar, and one page per app above it.
 *
 * This is the only ApplicationWindow in the merged process. Every app becomes
 * an Item that lives inside the StackLayout below, which is why the contract
 * asks each repo to split its ApplicationWindow off from its page content.
 *
 * The tab list comes from PdM.Core's AppRegistry rather than an array here, so
 * the tab bar and the page stack cannot disagree about what exists, and an app
 * turns its placeholder into a real tab by calling setPage() from its own
 * library -- without this file changing.
 */
ApplicationWindow {
    id: window

    /* Sized for the most demanding tab rather than for the shell. OTA asked
       for 1440x920 and refused to go below 1080 wide when it owned its own
       window; at the shell's original 1280x800 its guest table lost the whole
       actions column off the right edge. A tab cannot negotiate its own window
       size, so the window has to be at least as large as the largest tab
       wants. */
    width: 1440
    height: 920
    minimumWidth: 1080
    minimumHeight: 700
    visible: true
    title: qsTr("PdM Maestro")

    Material.theme: Theme.dark ? Material.Dark : Material.Light
    Material.accent: Theme.primary
    color: Theme.background

    /*
     * A2b's `navigate_to` tool (docs/SCOPE.md §6.2): the agent tab validates
     * the destination and publishes here; the shell is what actually owns
     * `tabBar.currentIndex`, so this is where the switch has to happen. An
     * unknown tab id -- already rejected server-side, but nothing stops a
     * future publisher from getting this topic wrong -- is just ignored
     * rather than crashing the shell: indexOf() returns -1, which is not a
     * valid StackLayout index.
     */
    BusSubscription {
        topic: "agent.navigate"
        onReceived: (payload) => {
            const idx = AppRegistry.indexOf(payload.tab);
            if (idx < 0)
                return;
            tabBar.setCurrentIndex(idx);
            if (payload.section)
                highlightRelay.fire(payload.tab, payload.section);
        }
    }

    /*
     * The second half of a guided "take me there and show me": once the tab
     * has actually switched, publish `agent.highlight` so the destination
     * page can flash the one element the agent named (server-validated
     * against a per-tab allowlist -- see server/tools.py's HIGHLIGHT_TARGETS
     * -- so this never receives a name nothing is listening for). A separate
     * publish, not folded into `agent.navigate` above, because the
     * destination page may still be mid-crossfade (this container's own
     * 220ms opacity transition) or, on a first visit, still instantiating --
     * either way it isn't ready to be highlighted the instant the tab
     * switches, only shortly after.
     */
    Timer {
        id: highlightRelay
        property string tab: ""
        property string element: ""
        interval: 350
        repeat: false
        function fire(tabId, element_) {
            tab = tabId;
            element = element_;
            restart();
        }
        onTriggered: MessageBus.publish("agent.highlight", { tab: tab, element: element })
    }

    /*
     * A plain Item, not StackLayout -- StackLayout hides every non-current
     * child outright (`visible: false`), which is instant by construction
     * and gives a switch nothing to animate. StackView was the other
     * candidate and was rejected: its push/pop model destroys popped pages
     * unless explicitly cached, which is exactly the "an app turns its
     * placeholder into a real tab and then never gets torn down" contract
     * the comment below already depends on. So every loaded page stays
     * exactly where it always was -- an always-visible `Loader`, sized by
     * anchors.fill like this container's own children were under
     * StackLayout -- and only `opacity` (with `enabled` alongside it, so a
     * fading-out page can't still catch a click) marks which one is current.
     * `currentIndex` was StackLayout's own property before; declared by
     * hand now that this is a bare Item.
     */
    Item {
        id: stack
        anchors.fill: parent
        property int currentIndex: tabBar.currentIndex

        Repeater {
            model: AppRegistry

            Loader {
                id: pageLoader
                anchors.fill: parent

                required property int index
                required property string title
                required property string glyph
                required property string moduleUri
                required property string repo
                required property string status
                required property url pageUrl
                required property bool available

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

                opacity: index === stack.currentIndex ? 1 : 0
                enabled: index === stack.currentIndex
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Component.onCompleted: if (index === stack.currentIndex) loaded = true

                Connections {
                    target: stack
                    function onCurrentIndexChanged() {
                        if (stack.currentIndex === pageLoader.index)
                            pageLoader.loaded = true
                    }
                }

                sourceComponent: pageLoader.available ? appPage : placeholderPage

                /* A nested Loader rather than binding `source` on the outer one:
                   Loader.source and Loader.sourceComponent clear each other, so
                   one Loader cannot hold a binding for both cases. */
                Component {
                    id: appPage
                    Loader { source: pageLoader.pageUrl }
                }

                Component {
                    id: placeholderPage
                    PlaceholderPage {
                        title: pageLoader.title
                        glyph: pageLoader.glyph
                        moduleUri: pageLoader.moduleUri
                        repo: pageLoader.repo
                        status: pageLoader.status
                    }
                }
            }
        }
    }

    /*
     * The stop strip, and the reason it lives in the shell rather than in the
     * tab that needs it.
     *
     * The motor rig's emergency stop has to be reachable at every moment. In a
     * standalone window that is easy -- the stop is on the only screen there is.
     * Merged into tabs, switching to OTA Update hides it while the shaft is
     * still turning, which is a hazard the integration created and no app can
     * fix from inside its own page.
     *
     * So an app arms PdM.Core's SafetyStop while something must stay
     * interruptible, and this strip appears above the tab bar until it is
     * disarmed -- on every tab, including the ones that have no idea a motor
     * exists.
     */
    footer: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            visible: SafetyStop.armed
            implicitHeight: 56
            color: Theme.danger

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacing
                spacing: Theme.spacing

                Text {
                    text: "\u25CF"
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textOnAccent
                    SequentialAnimation on opacity {
                        running: SafetyStop.armed
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: SafetyStop.summary
                    font.pixelSize: Theme.fontBody
                    font.weight: Font.DemiBold
                    color: Theme.textOnAccent
                    elide: Text.ElideRight
                }

                Button {
                    id: globalStop
                    text: qsTr("■  EMERGENCY STOP")
                    implicitHeight: 40
                    font.weight: Font.DemiBold
                    onClicked: SafetyStop.requestStop()

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: globalStop.down ? Theme.surfaceVariant : Theme.surface
                    }
                    contentItem: Text {
                        text: globalStop.text
                        font: globalStop.font
                        color: Theme.danger
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: Theme.spacing
                        rightPadding: Theme.spacing
                    }
                }
            }
        }

        Rectangle {
        Layout.fillWidth: true
        implicitHeight: tabBar.implicitHeight
        color: Theme.surface

        /* The tab bar sits on a surface, so it needs its own top edge to
           separate it from a page painted in the background colour. */
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Theme.outline
        }

        TabBar {
            id: tabBar
            anchors.fill: parent
            background: null

            /*
             * The Material style draws the active-tab underline as a ListView
             * `highlight` that slides to the current item over 250ms. It
             * disagreed with the rest of the bar at startup -- the label for tab
             * 0 correctly rendered as current while the underline sat under tab
             * 2 -- because the two are driven by different machinery: the label
             * by the currentIndex binding below, the underline by a shared
             * animated item positioned from the ListView's own layout, which
             * settles before the Repeater's buttons have their final widths.
             *
             * Replacing the highlight with a per-button underline puts both on
             * the same binding, so they cannot drift apart. The slide is lost;
             * for four fixed tabs it was not carrying much.
             */
            contentItem: ListView {
                model: tabBar.contentModel
                currentIndex: tabBar.currentIndex
                orientation: ListView.Horizontal
                spacing: tabBar.spacing
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.AutoFlickIfNeeded
                snapMode: ListView.SnapToItem
                highlight: null
            }

            /* Without this the window opens on the second tab. A TabBar whose
               buttons come from a Repeater does not reliably settle on index 0:
               the Container tracks the item being inserted, so the last
               insertion to complete wins. Assigning after construction rather
               than binding currentIndex leaves the user's own clicks alone. */
            Component.onCompleted: tabBar.setCurrentIndex(0)

            Repeater {
                model: AppRegistry

                TabButton {
                    id: tabButton

                    required property int index
                    required property string title
                    required property string glyph

                    readonly property bool current: tabBar.currentIndex === index

                    padding: Theme.spacingTight

                    /* The underline that replaces the Material highlight, on
                       the same binding as the label colours above. */
                    background: Item {
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 2
                            color: Theme.primary
                            visible: tabButton.current
                        }
                    }

                    contentItem: ColumnLayout {
                        spacing: 2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tabButton.glyph
                            font.pixelSize: 20
                            color: tabButton.current ? Theme.primary : Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: tabButton.title
                            font.pixelSize: Theme.fontSmall
                            font.weight: tabButton.current ? Font.DemiBold : Font.Normal
                            color: tabButton.current ? Theme.primary : Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }
        }
        }
    }
}
