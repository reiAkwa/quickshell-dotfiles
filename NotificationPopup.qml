import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// One layer-shell overlay per monitor that stacks the newest notifications in
// the top-right corner. It never takes keyboard focus, so it cannot steal
// input from the focused window.
PanelWindow {
  id: root

  required property var modelData

  screen: modelData
  visible: Notifications.live.length > 0

  anchors {
    top: true
    right: true
  }
  margins.top: Theme.barHeight + 8
  margins.right: 8

  implicitWidth: 360
  implicitHeight: Math.max(1, stack.implicitHeight)

  color: "transparent"
  focusable: false
  exclusiveZone: -1
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Column {
    id: stack

    width: root.width
    spacing: 8

    Repeater {
      model: Notifications.live

      NotificationToast {
        required property var modelData

        notification: modelData
        onClosed: Notifications.closeToast(modelData)
      }
    }
  }
}
