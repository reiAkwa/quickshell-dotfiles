import QtQuick
import QtQuick.Layouts

// One action row for Spotlight's !command and =calculator modes. Application
// results use the ListView delegate in Spotlight.qml instead.
Item {
  id: root

  property string symbol: ""
  property string title: ""
  property string subtitle: ""
  property string actionText: ""
  property bool active: false
  property color inactiveBackground: "transparent"
  property color inactiveTitleColor: Theme.textSecondary
  property int activeTitleSize: 13

  signal activated

  implicitHeight: 46

  Rectangle {
    anchors {
      fill: parent
      leftMargin: 6
      rightMargin: 6
      topMargin: 2
      bottomMargin: 2
    }
    radius: 8
    color: root.active ? Theme.accent : root.inactiveBackground
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.active
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }

  RowLayout {
    anchors {
      fill: parent
      leftMargin: 16
      rightMargin: 16
    }
    spacing: 12

    Text {
      Layout.preferredWidth: 24
      horizontalAlignment: Text.AlignHCenter
      text: root.symbol
      color: root.active ? Theme.accentText : Theme.accent
      font.family: Theme.fontFamily
      font.pixelSize: 20
      font.bold: true
      textFormat: Text.PlainText
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      Text {
        Layout.fillWidth: true
        text: root.title
        color: root.active ? Theme.accentText : root.inactiveTitleColor
        font.family: Theme.fontFamily
        font.pixelSize: root.active ? root.activeTitleSize : 13
        font.bold: true
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        Layout.fillWidth: true
        text: root.subtitle
        color: root.active ? Theme.accentText : Theme.textMuted
        opacity: root.active ? 0.8 : 1
        font.family: Theme.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }

    Text {
      visible: root.actionText !== "" && root.active
      text: root.actionText
      color: Theme.accentText
      opacity: 0.8
      font.family: Theme.fontFamily
      font.pixelSize: 10
      textFormat: Text.PlainText
    }
  }
}
