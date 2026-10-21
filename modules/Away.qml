import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"

// Coffee button next to the notification bell. While enabled it holds an
// idle inhibitor on a tiny transparent overlay surface, so swayidle / niri do
// not blank or lock the screen.
Module {
  id: root

  property string screenName: ""

  readonly property var targetScreen: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === screenName)
        return screens[i];
    }
    return null;
  }

  // Icon-only: the bar is already dense, so no text label.
  text: ""
  leadingIcon: "\uf0f4"
  textColor: Theme.foreground
  moduleColor: StayAwake.active
    ? (containsMouse ? Qt.lighter(Theme.awayActive, 1.08) : Theme.awayActive)
    : (containsMouse ? Qt.lighter(Theme.window, 1.08) : Theme.window)

  onClicked: {
    StayAwake.active = !StayAwake.active;
  }

  // A top-layer bar is covered by fullscreen windows in niri, and niri only
  // honors inhibitors on surfaces that are actually visible. This 1x1
  // transparent overlay stays mapped above fullscreen content, which keeps
  // the inhibitor effective there as well.
  PanelWindow {
    id: inhibitorSurface

    screen: root.targetScreen
    visible: StayAwake.active
    color: "transparent"
    focusable: false
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      left: true
    }
    implicitWidth: 1
    implicitHeight: 1
  }

  IdleInhibitor {
    window: inhibitorSurface
    enabled: StayAwake.active
  }
}

