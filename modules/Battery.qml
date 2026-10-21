import Quickshell.Services.UPower
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

  visible: present
  text: capacity + "% "
  trailingIcon: icons[Math.round(capacity * (icons.length - 1) / 100)]
  moduleColor: Theme.battery
}
