import QtQuick
import QtQuick.Layouts
import PdM.Shell

/*
 * Stands in for a tab whose app has not been merged yet.
 *
 * It is an Item and not an ApplicationWindow, which is the single most
 * important thing about it: it is the shape every real page has to take, so
 * this file doubles as the smallest possible example of the contract. When
 * PdM.DataCollection ships a DataCollectionPage, the Loader in Main.qml swaps
 * one for the other and nothing else changes.
 *
 * It reports the migration state rather than saying "coming soon", so the four
 * tabs are a live picture of where the integration actually stands.
 */
Item {
    id: root

    /* Mirrors the fields of one entry in Main.qml's `apps` array. */
    property string title: ""
    property string glyph: ""
    property string moduleUri: ""
    property string repo: ""
    property string status: ""

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacingWide * 2, 520)
        spacing: Theme.spacing

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.glyph
            font.pixelSize: 56
            color: Theme.textDisabled
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.title
            font.pixelSize: Theme.fontDisplay
            font.weight: Font.DemiBold
            color: Theme.textPrimary
        }

        Text {
            Layout.fillWidth: true
            text: root.status
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontBody
            color: Theme.textSecondary
        }

        /* The two identifiers the port has to claim: the QML module URI the app
           will register, and the repository it comes from. Keeping them on
           screen means the contract is never more than a glance away. */
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing
            implicitHeight: details.implicitHeight + Theme.spacing * 2
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            radius: Theme.radius

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: Theme.spacing
                spacing: Theme.spacingTight

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing
                    Text {
                        text: qsTr("module")
                        font.pixelSize: Theme.fontTiny
                        color: Theme.textDisabled
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: root.moduleUri
                        elide: Text.ElideLeft
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textPrimary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing
                    Text {
                        text: qsTr("repo")
                        font.pixelSize: Theme.fontTiny
                        color: Theme.textDisabled
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: root.repo
                        elide: Text.ElideLeft
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textPrimary
                    }
                }
            }
        }
    }
}
