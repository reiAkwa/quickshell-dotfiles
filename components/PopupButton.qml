import QtQuick

// Small pill-shaped button used by the interactive bar popouts.
Rectangle {
  id: root

  property string text: ""
  property bool primary: false
  property bool available: true
  property int maxTextWidth: -1

  signal clicked

  implicitWidth: (maxTextWidth > 0
    ? Math.min(label.implicitWidth, maxTextWidth)
    : label.implicitWidth) + 16
  implicitHeight: 22
  radius: height / 2
  color: !available
    ? "#c8d2dc"
    : (primary ? Theme.accent : (mouse.containsMouse ? "#cfdeea" : "#dce7f0"))
  opacity: available ? 1 : 0.65

  Text {
    id: label
    anchors.centerIn: parent
    width: root.maxTextWidth > 0
      ? Math.min(implicitWidth, root.maxTextWidth)
      : implicitWidth
    text: root.text
    color: root.primary ? Theme.background : Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: 11
    elide: Text.ElideRight
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.available
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
