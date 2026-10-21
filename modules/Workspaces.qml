import QtQuick
import Quickshell.Io
import "../components"

Row {
  id: root

  property var workspaces: []

  // Always keep three workspace slots so the bar never collapses when niri
  // only reports the workspace that currently exists.
  readonly property int minimumWorkspaces: 3

  readonly property var displayWorkspaces: {
    const sorted = workspaces.slice().sort((a, b) => a.idx - b.idx);
    const firstIndex = sorted.length > 0 ? sorted[0].idx : 1;
    const lastIndex = sorted.length > 0
      ? Math.max(sorted[sorted.length - 1].idx, firstIndex + minimumWorkspaces - 1)
      : minimumWorkspaces;

    const result = [];
    for (let index = firstIndex; index <= lastIndex; index++) {
      const workspace = sorted.find(item => item.idx === index);
      result.push({
        idx: index,
        // Icon position is relative to this output's first workspace, so the
        // three fixed icons stay in order on every monitor.
        position: index - firstIndex,
        isFocused: workspace ? !!workspace.is_focused : false,
        exists: !!workspace
      });
    }
    return result;
  }

  height: Theme.moduleHeight
  spacing: 0

  function focusWorkspace(index) {
    focusProcess.command = ["niri", "msg", "action", "focus-workspace", String(index)];
    focusProcess.running = true;
  }

  // The first three slots get fixed icons; later slots are blank buttons.
  function iconFor(position) {
    switch (position) {
    case 0: return "\uf120"; // fa-terminal
    case 1: return "\uf0ac"; // fa-globe
    case 2: return "\uf1d6"; // fa-qq
    default: return "";
    }
  }

  Repeater {
    model: root.displayWorkspaces

    Item {
      id: button
      required property var modelData

      width: Theme.workspaceButtonWidth
      height: root.height

      Rectangle {
        anchors.fill: parent
        radius: Theme.moduleRadius
        color: button.modelData.isFocused
          ? Theme.accent
          : Theme.workspaceInactive

        Behavior on color {
          ColorAnimation { duration: 120 }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: button.modelData.position < 3
        text: root.iconFor(button.modelData.position)
        color: button.modelData.isFocused
          ? Theme.background
          : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        textFormat: Text.PlainText

        Behavior on color {
          ColorAnimation { duration: 120 }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusWorkspace(button.modelData.idx)
      }
    }
  }

  Process {
    id: focusProcess
    command: ["niri", "msg", "action", "focus-workspace", "1"]
  }
}
