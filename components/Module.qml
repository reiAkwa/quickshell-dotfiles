import QtQuick

// The rounded, padded module background used by every Waybar module in the
// original style.css.
Item {
  id: root

  property color moduleColor: Theme.window
  property color textColor: Theme.foreground
  property string leadingIcon: ""
  property string trailingIcon: ""
  property alias text: label.text
  property alias textItem: label
  property alias containsMouse: mouse.containsMouse
  property int maxTextWidth: -1
  property real letterSpacing: 0

  signal clicked
  signal rightClicked
  signal scrolled(int delta)

  // Hover, mute and press feedback is eased instead of snapping. The bar
  // keeps its layout because only the module surface is scaled a touch while
  // the pointer is held down.
  scale: mouse.pressed ? 0.97 : 1

  Behavior on scale {
    NumberAnimation {
      duration: Theme.motionFast
      easing.type: Theme.easeStandard
    }
  }

  Behavior on moduleColor {
    ColorAnimation {
      duration: Theme.motionFast
      easing.type: Theme.easeStandard
    }
  }

  Behavior on textColor {
    ColorAnimation {
      duration: Theme.motionFast
      easing.type: Theme.easeStandard
    }
  }

  implicitWidth: contentRow.implicitWidth + Theme.modulePadding * 2
  implicitHeight: Theme.moduleHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.moduleRadius
    color: root.moduleColor
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 0

    Glyph {
      visible: root.leadingIcon !== ""
      icon: root.leadingIcon
      color: root.textColor
    }

    Text {
      id: label
      width: root.maxTextWidth > 0
        ? Math.min(implicitWidth, root.maxTextWidth)
        : implicitWidth
      color: root.textColor
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      font.letterSpacing: root.letterSpacing
      textFormat: Text.PlainText
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    Glyph {
      visible: root.trailingIcon !== ""
      icon: root.trailingIcon
      color: root.textColor
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: event => {
      if (event.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
    onWheel: event => {
      root.scrolled(event.angleDelta.y > 0 ? 1 : -1)
      event.accepted = true
    }
  }
}
