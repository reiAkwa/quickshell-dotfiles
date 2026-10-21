pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import ".."
import "../components"

Module {
  id: root

  readonly property var device: UPower.displayDevice
  readonly property bool present: device && device.ready && device.isPresent
  readonly property int capacity: {
    if (!device || !device.ready)
      return 0;
    const value = device.percentage;
    return Math.round(value <= 1 ? value * 100 : value);
  }

  readonly property var icons: [
    "\uf244", // 
    "\uf243", // 
    "\uf242", // 
    "\uf241", // 
    "\uf240"  // 
  ]

  // asusd writes the active platform profile here, and ROG Control Center
  // changes it through asusd. Watching the sysfs attribute keeps the bar in
  // sync no matter which side changes the profile.
  property string powerProfile: ""

  readonly property string profileIcon: {
    if (powerProfile === "quiet")
      return "\uf186"; // moon
    if (powerProfile === "balanced")
      return "\uf24e"; // scale
    if (powerProfile === "performance")
      return "\uf0e4"; // gauge
    return "";
  }

  visible: present
  leadingIcon: profileIcon
  text: (profileIcon !== "" ? " " : "") + capacity + "% "
  trailingIcon: icons[Math.round(capacity * (icons.length - 1) / 100)]
  moduleColor: containsMouse ? Qt.lighter(Theme.battery, 1.15) : Theme.battery

  onClicked: openControlCenter()
  onRightClicked: nextProfile.running = true

  // rog-control-center's single-instance path only calls show() on an already
  // visible window, which does not raise it under niri. Focus the existing
  // toplevel when there is one, otherwise ask rogcc to open its window.
  function openControlCenter() {
    for (let i = 0; i < Niri.windows.length; i++) {
      const window = Niri.windows[i];
      if (window.app_id === "rog-control-center") {
        Quickshell.execDetached([
          "niri", "msg", "action", "focus-window", "--id", String(window.id)
        ]);
        return;
      }
    }
    Quickshell.execDetached(["rog-control-center"]);
  }

  FileView {
    id: profileFile

    path: "/sys/firmware/acpi/platform_profile"
    watchChanges: true
    printErrors: false

    onFileChanged: reload()
    onLoaded: root.powerProfile = text().trim()
  }

  Process {
    id: nextProfile

    command: ["asusctl", "profile", "next"]
    running: false
  }
}
