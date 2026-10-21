pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"

// Shared popout for the CPU and memory modules. Both modules only change the
// popout key; all process sampling lives in Tasks.qml and this panel just
// presents one snapshot.
PanelWindow {
  id: root

  property string screenName: ""
  property int pendingKillPid: -1

  readonly property string popupKey: screenName + ":tasks"
  readonly property bool panelOpen: Popout.current === popupKey

  readonly property var targetScreen: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === screenName)
        return screens[i];
    }
    return null;
  }

  screen: root.targetScreen
  visible: root.panelOpen
  color: "transparent"
  focusable: true
  exclusiveZone: -1
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.panelOpen
    ? WlrKeyboardFocus.Exclusive
    : WlrKeyboardFocus.None

  anchors {
    top: true
    left: true
    right: true
    bottom: true
  }
  margins.top: Theme.barHeight

  onPanelOpenChanged: {
    Tasks.setPanelOpen(root.panelOpen);
    root.pendingKillPid = -1;
  }

  Component.onCompleted: Tasks.setPanelOpen(root.panelOpen)

  Timer {
    id: pendingKillTimer
    interval: 3000
    repeat: false
    onTriggered: root.pendingKillPid = -1
  }

  // Same overlay pattern as the audio/network panels: the bar is a
  // layer-shell surface, so an xdg_popup cannot be attached to it.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: Popout.close(root.popupKey)
    onWheel: event => event.accepted = true
  }

  Rectangle {
    width: 460
    height: Math.min(560, parent.height - 8)
    x: Math.max(8, Math.min(Tasks.anchorRight - width, parent.width - width - 8))
    y: 4
    radius: Theme.moduleRadius
    color: Theme.background
    border.width: 1
    border.color: Theme.accent
    clip: true

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: {}
      onWheel: event => event.accepted = true
    }

    ColumnLayout {
      id: panelContent

      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        bottom: parent.bottom
        margins: 12
      }
      spacing: 8
      focus: true

      Keys.onEscapePressed: Popout.close(root.popupKey)

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: "Task Manager"
          color: Theme.foreground
          font.family: Theme.fontFamily
          font.pixelSize: 16
          font.bold: true
        }

        Item {
          Layout.fillWidth: true
        }

        Text {
          text: Tasks.cpuCount + (Tasks.cpuCount === 1 ? " core" : " cores")
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 11
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 16

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignTop
          spacing: 4

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
              text: "CPU"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 10
              font.bold: true
            }

            Item {
              Layout.fillWidth: true
            }

            Text {
              text: Tasks.cpuUsage + "%"
              color: Theme.cpu
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.bold: true
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Theme.inactive

            Rectangle {
              width: parent.width * Math.max(0, Math.min(100, Tasks.cpuUsage)) / 100
              height: parent.height
              radius: 3
              color: Theme.cpu
            }
          }

          Text {
            Layout.fillWidth: true
            text: Tasks.cpuUsage + "% overall"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignTop
          spacing: 4

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
              text: "Memory"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 10
              font.bold: true
            }

            Item {
              Layout.fillWidth: true
            }

            Text {
              text: Tasks.memoryPercentage + "%"
              color: Theme.memory
              font.family: Theme.fontFamily
              font.pixelSize: 11
              font.bold: true
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Theme.inactive

            Rectangle {
              width: parent.width * Math.max(0, Math.min(100, Tasks.memoryPercentage)) / 100
              height: parent.height
              radius: 3
              color: Theme.memory
            }
          }

          Text {
            Layout.fillWidth: true
            text: Tasks.formatBytes(Tasks.memoryUsedBytes) + " / "
              + Tasks.formatBytes(Tasks.memoryTotalBytes)
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }

          Text {
            Layout.fillWidth: true
            visible: Tasks.swapTotalBytes > 0
            text: "Swap " + Tasks.formatBytes(Tasks.swapUsedBytes) + " / "
              + Tasks.formatBytes(Tasks.swapTotalBytes)
              + " (" + Tasks.swapPercentage + "%)"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.divider
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: "PROCESSES"
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 10
          font.bold: true
        }

        PopupButton {
          text: "CPU"
          primary: Tasks.sortKey === "cpu"
          onClicked: Tasks.sortKey = "cpu"
        }

        PopupButton {
          text: "Memory"
          primary: Tasks.sortKey === "memory"
          onClicked: Tasks.sortKey = "memory"
        }

        PopupButton {
          text: "Name"
          primary: Tasks.sortKey === "name"
          onClicked: Tasks.sortKey = "name"
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 2
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: "Name"
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }

        Text {
          Layout.preferredWidth: 54
          horizontalAlignment: Text.AlignRight
          text: "PID"
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }

        Text {
          Layout.preferredWidth: 54
          horizontalAlignment: Text.AlignRight
          text: "CPU"
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }

        Text {
          Layout.preferredWidth: 62
          horizontalAlignment: Text.AlignRight
          text: "MEM"
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }

        Item {
          Layout.preferredWidth: 62
        }
      }

      ListView {
        id: processList

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 120
        visible: Tasks.processCount > 0
        clip: true
        spacing: 1
        model: Tasks.processModel
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationWraps: false

        Keys.onEscapePressed: Popout.close(root.popupKey)

        delegate: Item {
          id: processRow

          required property int pid
          required property string name
          required property real cpu
          required property real rssBytes

          width: processList.width
          height: 32

          HoverHandler {
            id: rowHover
          }

          Rectangle {
            anchors.fill: parent
            radius: 6
            color: rowHover.hovered || root.pendingKillPid === processRow.pid
              ? Theme.rowHover
              : "transparent"
          }

          RowLayout {
            anchors {
              fill: parent
              leftMargin: 8
              rightMargin: 2
            }
            spacing: 8

            Text {
              Layout.fillWidth: true
              text: processRow.name
              color: processRow.cpu >= 50 ? Theme.accent : Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Text {
              Layout.preferredWidth: 54
              horizontalAlignment: Text.AlignRight
              text: processRow.pid
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }

            Text {
              Layout.preferredWidth: 54
              horizontalAlignment: Text.AlignRight
              text: Tasks.formatCpu(processRow.cpu)
              color: processRow.cpu >= 50 ? Theme.accent : Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }

            Text {
              Layout.preferredWidth: 62
              horizontalAlignment: Text.AlignRight
              text: Tasks.formatCompact(processRow.rssBytes)
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }

            PopupButton {
              Layout.preferredWidth: 62
              text: root.pendingKillPid === processRow.pid ? "Confirm" : "End"
              primary: root.pendingKillPid === processRow.pid
              enabled: processRow.pid > 1
                && (rowHover.hovered || root.pendingKillPid === processRow.pid)
              opacity: enabled ? 1 : 0
              onClicked: {
                if (root.pendingKillPid === processRow.pid) {
                  Tasks.terminate(processRow.pid);
                  root.pendingKillPid = -1;
                } else {
                  root.pendingKillPid = processRow.pid;
                  pendingKillTimer.restart();
                }
              }
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.preferredHeight: 160
        visible: Tasks.processCount === 0
        text: "Collecting process data…"
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: Tasks.processCount + " processes"
          color: Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }

        Text {
          text: root.pendingKillPid >= 0
            ? "Click Confirm to send SIGTERM"
            : "Esc / click outside to close"
          color: root.pendingKillPid >= 0 ? Theme.danger : Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: 10
        }
      }
    }
  }
}
