pragma Singleton

import Quickshell

// Shared state for the "away" button. Away.qml creates one dedicated
// overlay inhibitor surface per screen, so toggling away mode from one
// monitor also keeps the other monitors awake.
Singleton {
  id: root

  // PersistentProperties keeps the toggle across hot reloads. Editing an
  // unrelated QML file should not silently disable the inhibitor and let
  // swayidle lock the screen a few minutes later.
  property alias active: state.active

  PersistentProperties {
    id: state

    reloadableId: "stayAwake"
    property bool active: false
  }
}
