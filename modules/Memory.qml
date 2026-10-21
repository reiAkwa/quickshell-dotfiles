pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../components"

Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":tasks"

  property int percentage: 0

  text: percentage + "% "
  trailingIcon: "\uefc5"
  moduleColor: Theme.memory

  onClicked: {
    Tasks.anchorRight = root.mapToItem(null, root.width, 0).x;
    Popout.toggleAt(root.popupKey, "memory");
  }
}
