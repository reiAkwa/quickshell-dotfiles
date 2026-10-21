import QtQuick
import Quickshell
import "components"
import "modules"

PanelWindow {
  id: bar

  required property var modelData

  screen: modelData
  anchors {
    top: true
    left: true
    right: true
  }

  implicitHeight: Theme.barHeight
  exclusiveZone: Theme.barHeight
  color: "transparent"

  Rectangle {
    anchors.fill: parent
    color: Theme.background

    Rectangle {
      anchors {
        left: parent.left
        right: parent.right
        bottom: parent.bottom
      }
      height: Theme.borderWidth
      color: Theme.accent
    }
  }

  Item {
    id: content

    anchors {
      fill: parent
      bottomMargin: Theme.borderWidth
    }

    MouseArea {
      anchors.fill: parent
      onClicked: Popout.dismissFor(bar.screen.name)
    }

    Row {
      anchors {
        left: parent.left
        top: parent.top
        bottom: parent.bottom
      }
      spacing: 0

      Workspaces {
        workspaces: Niri.workspacesForOutput(bar.screen.name)
      }

      ActiveWindow {
        title: Niri.focusedWindow ? Niri.focusedWindow.title : ""
      }
    }

    Row {
      anchors {
        horizontalCenter: parent.horizontalCenter
        top: parent.top
        bottom: parent.bottom
      }
      spacing: 0

      Clock { screenName: bar.screen.name }
    }

    Row {
      anchors {
        right: parent.right
        top: parent.top
        bottom: parent.bottom
      }
      spacing: 0

      Audio { screenName: bar.screen.name }
      Network { screenName: bar.screen.name }
      Bluetooth { screenName: bar.screen.name }

      Cpu {
        usage: Stats.cpuUsage
      }

      Memory {
        percentage: Stats.memoryPercentage
      }

      Battery {}
      NotificationCenter { screenName: bar.screen.name }
      Away { screenName: bar.screen.name }
      Tray {}
    }
  }
}

