pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Niri has no Quickshell service module, so this listens to niri's own JSON
// event stream. The stream starts with WorkspacesChanged and WindowsChanged,
// which gives us the complete initial state.
Singleton {
  id: root

  property var workspaces: []
  property var windows: []

  readonly property var focusedWindow: {
    for (let i = 0; i < windows.length; i++) {
      if (windows[i].is_focused)
        return windows[i];
    }
    return null;
  }

  function workspacesForOutput(output) {
    return workspaces
      .filter(workspace => workspace.output === output)
      .slice()
      .sort((a, b) => a.idx - b.idx);
  }

  function handleEvent(line) {
    if (!line)
      return;

    let event;
    try {
      event = JSON.parse(line);
    } catch (error) {
      return;
    }

    if (event.WorkspacesChanged) {
      root.workspaces = event.WorkspacesChanged.workspaces;
      return;
    }

    if (event.WindowsChanged) {
      root.windows = event.WindowsChanged.windows;
      return;
    }

    if (event.WorkspaceActivated) {
      const workspaceId = event.WorkspaceActivated.id;
      const focused = event.WorkspaceActivated.focused;
      root.workspaces = root.workspaces.map(workspace => {
        if (workspace.id === workspaceId) {
          return Object.assign({}, workspace, {
            is_active: focused ? true : workspace.is_active,
            is_focused: focused
          });
        }
        return focused
          ? Object.assign({}, workspace, { is_focused: false })
          : workspace;
      });
      return;
    }

    if (event.WorkspaceUrgencyChanged) {
      const workspaceId = event.WorkspaceUrgencyChanged.id;
      const urgent = event.WorkspaceUrgencyChanged.urgent;
      root.workspaces = root.workspaces.map(workspace =>
        workspace.id === workspaceId
          ? Object.assign({}, workspace, { is_urgent: urgent })
          : workspace
      );
      return;
    }

    if (event.WindowOpenedOrChanged) {
      const changed = event.WindowOpenedOrChanged.window;
      const index = root.windows.findIndex(window => window.id === changed.id);
      if (index === -1)
        root.windows = root.windows.concat([changed]);
      else
        root.windows = root.windows.map(window =>
          window.id === changed.id ? changed : window
        );
      return;
    }

    if (event.WindowClosed) {
      const windowId = event.WindowClosed.id;
      root.windows = root.windows.filter(window => window.id !== windowId);
      return;
    }

    if (event.WindowFocusChanged) {
      const windowId = event.WindowFocusChanged.id;
      root.windows = root.windows.map(window =>
        Object.assign({}, window, { is_focused: window.id === windowId })
      );
      return;
    }

    if (event.WindowUrgencyChanged) {
      const windowId = event.WindowUrgencyChanged.id;
      const urgent = event.WindowUrgencyChanged.urgent;
      root.windows = root.windows.map(window =>
        window.id === windowId
          ? Object.assign({}, window, { is_urgent: urgent })
          : window
      );
    }
  }

  Process {
    id: eventStream

    command: ["niri", "msg", "--json", "event-stream"]
    running: true

    stdout: SplitParser {
      onRead: line => root.handleEvent(line)
    }

    onExited: restartTimer.start()
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: eventStream.running = true
  }
}
