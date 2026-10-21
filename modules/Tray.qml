pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../components"

Module {
  id: root

  readonly property var items: SystemTray.items.values.filter(
    item => item.status !== Status.Passive
  )

  function resolveIcon(icon) {
    if (!icon)
      return Quickshell.iconPath("image-missing");
    if (icon.startsWith("image://"))
      return icon;
    if (icon.startsWith("/"))
      return "file://" + icon;

    // Adwaita's symbolic SVGs do not always load through Qt's icon loader.
    // The non-symbolic variant is visually equivalent at tray size.
    const name = icon.endsWith("-symbolic")
      ? icon.slice(0, -"-symbolic".length)
      : icon;
    return Quickshell.iconPath(name, "image-missing");
  }

  implicitWidth: trayRow.width + Theme.modulePadding * 2
  moduleColor: Theme.tray

  Row {
    id: trayRow
    anchors.centerIn: parent
    spacing: 0

    Repeater {
      model: root.items

      Item {
        id: trayItem
        required property var modelData

        width: Theme.trayIconSize
        height: Theme.trayIconSize

        Image {
          anchors.centerIn: parent
          width: Theme.trayIconSize
          height: Theme.trayIconSize
          sourceSize.width: Theme.trayIconSize
          sourceSize.height: Theme.trayIconSize
          source: root.resolveIcon(trayItem.modelData.icon)
          smooth: true
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: event => {
            if (event.button === Qt.RightButton && trayItem.modelData.hasMenu)
              trayMenu.open();
            else
              trayItem.modelData.activate();
          }
        }

        QsMenuAnchor {
          id: trayMenu
          menu: trayItem.modelData.menu
          anchor.item: mouse
          anchor.edges: Edges.Bottom | Edges.Left
          anchor.gravity: Edges.Bottom | Edges.Right
        }
      }
    }
  }
}
