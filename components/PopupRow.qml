import QtQuick
import QtQuick.Layouts

// One entry in a network/bluetooth popout. Clicking anywhere on the row runs
// the same action as its trailing button.
Item {
  id: root

  property string icon: ""
  property color iconColor: Theme.foreground
  property string title: ""
  property string subtitle: ""
  property string actionText: ""
  property bool actionPrimary: false
  property bool actionEnabled: true
  property bool interactive: true

  signal clicked
  signal rightClicked

  implicitHeight: 40

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: mouse.containsMouse && root.interactive ? Theme.rowHover : "transparent"

    Behavior on color {
      ColorAnimation {
        duration: Theme.motionFast
        easing.type: Theme.easeStandard
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: event => {
      if (event.button === Qt.RightButton)
        root.rightClicked();
      else
        root.clicked();
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors {
      leftMargin: 8
      rightMargin: 6
    }
    spacing: 8

    Text {
      Layout.preferredWidth: 20
      horizontalAlignment: Text.AlignHCenter
      text: root.icon
      color: root.iconColor
      font.family: Theme.fontFamily
      font.pixelSize: 16
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      Text {
        Layout.fillWidth: true
        text: root.title
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 13
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        Layout.fillWidth: true
        text: root.subtitle
        visible: text !== ""
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }

    PopupButton {
      visible: root.actionText !== ""
      text: root.actionText
      primary: root.actionPrimary
      available: root.actionEnabled
      onClicked: root.clicked()
    }
  }
}
