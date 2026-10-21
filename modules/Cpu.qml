import QtQuick
import Quickshell
import Quickshell.Io
import "../components"

Module {
  property int usage: 0

  text: usage + "% "
  trailingIcon: "\uf4bc"
  moduleColor: Theme.cpu

  onClicked: htopProcess.running = true

  Process {
    id: htopProcess
    command: ["wezterm", "-e", "htop"]
    running: false
  }
}
