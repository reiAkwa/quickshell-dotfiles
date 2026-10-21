pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../components"

Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":tasks"

  property int usage: 0

  text: usage + "% "
  trailingIcon: "\uf4bc"
  moduleColor: Theme.cpu

  onClicked: {
    Tasks.anchorRight = root.mapToItem(null, root.width, 0).x;
    Popout.toggleAt(root.popupKey, "cpu");
  }
}
