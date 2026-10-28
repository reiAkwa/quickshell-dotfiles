import QtQuick

// Horizontal volume slider used by the audio mixer popout. `value` is always
// 0..1; dragging or scrolling emits `moved` and leaves the actual write to the
// caller, so the same control works for sinks, sources and application
// streams.
Item {
  id: root

  property real value: 0
  property bool muted: false
  property bool interactive: true
  property color fillColor: Theme.accent
  property color trackColor: Theme.divider

  signal moved(real value)

  readonly property real clampedValue: Math.max(0, Math.min(1, root.value))
  readonly property color activeColor: root.muted ? Theme.textMuted : root.fillColor

  implicitHeight: 18

  Rectangle {
    id: track

    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 5
    radius: 2.5
    color: root.trackColor
  }

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: track.width * root.clampedValue
    height: track.height
    radius: track.radius
    color: root.activeColor

    // Dragging must stay 1:1 with the pointer, so the fill only eases for
    // wheel and API volume changes.
    Behavior on width {
      enabled: !area.pressed
      NumberAnimation {
        duration: Theme.motionFast
        easing.type: Theme.easeStandard
      }
    }

    Behavior on color {
      ColorAnimation {
        duration: Theme.motionFast
        easing.type: Theme.easeStandard
      }
    }
  }

  Rectangle {
    id: knob

    width: 12
    height: 12
    radius: 6
    x: Math.max(0, Math.min(parent.width - width,
      root.clampedValue * parent.width - width / 2))
    y: (parent.height - height) / 2
    color: root.activeColor
    border.width: area.containsMouse || area.pressed ? 2 : 0
    border.color: Theme.background

    Behavior on x {
      enabled: !area.pressed
      NumberAnimation {
        duration: Theme.motionFast
        easing.type: Theme.easeStandard
      }
    }

    Behavior on color {
      ColorAnimation {
        duration: Theme.motionFast
        easing.type: Theme.easeStandard
      }
    }

    Behavior on border.width {
      NumberAnimation {
        duration: Theme.motionFast
        easing.type: Theme.easeStandard
      }
    }
  }

  MouseArea {
    id: area

    anchors.fill: parent
    anchors.topMargin: -5
    anchors.bottomMargin: -5
    enabled: root.interactive
    hoverEnabled: true
    preventStealing: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    function updateFromX(x) {
      root.moved(Math.max(0, Math.min(1, x / width)));
    }

    onPressed: mouse => updateFromX(mouse.x)
    onPositionChanged: mouse => {
      if (pressed)
        updateFromX(mouse.x);
    }
    onWheel: wheel => {
      root.moved(Math.max(0, Math.min(1,
        root.value + (wheel.angleDelta.y > 0 ? 0.02 : -0.02))));
      wheel.accepted = true;
    }
  }
}
