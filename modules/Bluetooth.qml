pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import "../components"

Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":bluetooth"
  readonly property bool panelOpen: Popout.current === popupKey

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool powered: adapter !== null && adapter.enabled

  property int sortRevision: 0
  property string pendingPairAddress: ""
  property string errorText: ""
  property real anchorRightCache: 0

  readonly property var targetScreen: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === screenName)
        return screens[i];
    }
    return null;
  }

  readonly property var sortedDevices: {
    root.sortRevision;
    const list = Bluetooth.devices.values.filter(
      device => (root.adapter === null || device.adapter === root.adapter)
        && root.usableDevice(device)
    );
    list.sort((a, b) => {
      return (root.deviceRank(a) - root.deviceRank(b))
        || root.deviceName(a).localeCompare(root.deviceName(b));
    });
    return list;
  }

  visible: adapter !== null
  text: powered ? "" : " Off"
  leadingIcon: "\uf293"
  textColor: powered ? Theme.foreground : "#7b8794"
  moduleColor: powered
    ? (containsMouse ? Qt.lighter(Theme.bluetooth, 1.12) : Theme.bluetooth)
    : Theme.window

  onClicked: Popout.toggle(popupKey)
  onRightClicked: {
    if (adapter)
      adapter.enabled = !adapter.enabled;
  }

  onPanelOpenChanged: {
    errorText = "";
    sortRevision++;
    if (panelOpen) {
      updateAnchor();
      startScan();
    } else {
      stopScan();
    }
  }

  onAdapterChanged: {
    if (panelOpen && adapter)
      startScan();
    else if (!adapter)
      stopScan();
  }

  function updateAnchor() {
    anchorRightCache = root.mapToItem(null, root.width, 0).x;
  }

  Connections {
    target: root.adapter

    function onEnabledChanged() {
      if (!root.adapter)
        return;
      if (root.powered && root.panelOpen)
        root.startScan();
      else
        root.stopScan();
    }
  }

  function deviceRank(device) {
    if (device.connected)
      return 0;
    if (device.bonded || device.paired)
      return 1;
    return 2;
  }

  function usableDevice(device) {
    if (!device)
      return false;
    if (device.connected || device.bonded || device.paired)
      return true;

    const name = device.name || device.deviceName;
    if (!name)
      return false;

    // BlueZ exposes many unnamed BLE devices under their MAC address. Showing
    // those would bury the devices the user can actually identify.
    return !/^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(name);
  }

  function deviceName(device) {
    return device.name || device.deviceName || device.address;
  }

  function deviceIcon(device) {
    const icon = device.icon || "";
    if (icon.indexOf("headset") !== -1
        || icon.indexOf("headphone") !== -1
        || icon.indexOf("audio") !== -1)
      return "\uf025";
    if (icon.indexOf("keyboard") !== -1)
      return "\uf11c";
    if (icon.indexOf("mouse") !== -1)
      return "\uf8cc";
    if (icon.indexOf("phone") !== -1)
      return "\uf10b";
    if (icon.indexOf("computer") !== -1)
      return "\uf108";
    if (icon.indexOf("gamepad") !== -1 || icon.indexOf("joystick") !== -1)
      return "\uf11b";
    return "\uf293";
  }

  function batteryText(device) {
    if (!device.batteryAvailable)
      return "";
    const battery = device.battery <= 1
      ? Math.round(device.battery * 100)
      : Math.round(device.battery);
    return battery + "%";
  }

  function deviceSubtitle(device) {
    if (device.pairing)
      return "Pairing…";
    if (device.state === BluetoothDeviceState.Connecting)
      return "Connecting…";
    if (device.state === BluetoothDeviceState.Disconnecting)
      return "Disconnecting…";
    if (device.connected) {
      const battery = batteryText(device);
      return battery === "" ? "Connected" : "Connected · " + battery;
    }
    if (device.bonded || device.paired)
      return "Paired";
    return "Available";
  }

  function deviceAction(device) {
    if (device.pairing)
      return "Pairing…";
    if (device.state === BluetoothDeviceState.Connecting)
      return "Connecting…";
    if (device.state === BluetoothDeviceState.Disconnecting)
      return "Disconnecting…";
    return device.connected ? "Disconnect" : "Connect";
  }

  function activateDevice(device) {
    if (!device || !powered)
      return;

    errorText = "";

    if (device.connected) {
      device.disconnect();
      return;
    }

    if (device.state === BluetoothDeviceState.Connecting
        || device.state === BluetoothDeviceState.Disconnecting
        || device.pairing)
      return;

    if (!device.bonded && !device.paired) {
      pendingPairAddress = device.address;
      pairTimer.restart();
      device.pair();
      return;
    }

    device.connect();
  }

  function startScan() {
    if (!adapter || !adapter.enabled)
      return;
    adapter.discovering = true;
    scanTimer.restart();
  }

  function stopScan() {
    scanTimer.stop();
    if (adapter)
      adapter.discovering = false;
  }

  function toggleScan() {
    if (!adapter || !adapter.enabled)
      return;
    if (adapter.discovering)
      stopScan();
    else
      startScan();
  }

  Timer {
    id: scanTimer
    interval: 15000
    onTriggered: root.stopScan()
  }

  Timer {
    id: pairTimer
    interval: 20000
    onTriggered: {
      if (root.pendingPairAddress !== "") {
        root.pendingPairAddress = "";
        root.errorText = "Pairing timed out.";
      }
    }
  }

  Timer {
    interval: 500
    running: root.panelOpen
    repeat: true
    onTriggered: root.updateAnchor()
  }

  // The bar is a layer-shell surface, so Qt cannot attach a grabbing xdg_popup
  // to it. Use a sibling overlay panel instead, which can take keyboard focus.
  PanelWindow {
    id: panel

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

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: Popout.close(root.popupKey)
      onWheel: event => event.accepted = true
    }

    Rectangle {
      width: 340
      height: panelContent.implicitHeight + 24
      x: Math.max(8, Math.min(root.anchorRightCache - width, parent.width - width - 8))
      y: 4
      radius: Theme.moduleRadius
      color: Theme.background
      border.width: 1
      border.color: Theme.accent

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
          margins: 12
        }
        spacing: 8
        focus: true

        Keys.onEscapePressed: Popout.close(root.popupKey)

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "Bluetooth"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          Item {
            Layout.fillWidth: true
          }

          Text {
            text: root.adapter === null
              ? "Unavailable"
              : (root.powered ? "On" : "Off")
            color: root.powered ? Theme.accent : "#6d7c8a"
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: "#c9d6e2"
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 34
          radius: 6
          color: adapterToggleMouse.containsMouse && root.adapter ? "#e4eef7" : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors {
              leftMargin: 6
              rightMargin: 8
            }
            spacing: 8

            Text {
              text: "\uf293"
              color: root.powered ? Theme.accent : "#6d7c8a"
              font.family: Theme.fontFamily
              font.pixelSize: 16
            }

            Text {
              Layout.fillWidth: true
              text: "Adapter"
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: 13
            }

            Rectangle {
              Layout.preferredWidth: 32
              Layout.preferredHeight: 18
              radius: 9
              color: root.powered ? Theme.accent : "#c8d2dc"

              Rectangle {
                width: 14
                height: 14
                radius: 7
                y: 2
                x: root.powered ? parent.width - width - 2 : 2
                color: "#ffffff"

                Behavior on x {
                  NumberAnimation { duration: 100 }
                }
              }
            }
          }

          MouseArea {
            id: adapterToggleMouse
            anchors.fill: parent
            enabled: root.adapter !== null
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              if (!root.adapter)
                return;
              root.errorText = "";
              root.adapter.enabled = !root.adapter.enabled;
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: 24
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: "Devices"
            color: "#6d7c8a"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            visible: root.adapter !== null && root.adapter.discovering
            text: "Scanning…"
            color: "#6d7c8a"
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }

          PopupButton {
            text: root.adapter !== null && root.adapter.discovering ? "Stop" : "Scan"
            available: root.powered
            onClicked: root.toggleScan()
          }
        }

        Flickable {
          id: deviceFlick

          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(deviceColumn.implicitHeight, 320)
          contentWidth: width
          contentHeight: deviceColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: deviceColumn
            width: deviceFlick.width
            spacing: 2

            Text {
              width: deviceColumn.width
              visible: !root.powered
              text: "Bluetooth is off"
              color: "#6d7c8a"
              font.family: Theme.fontFamily
              font.pixelSize: 12
              leftPadding: 8
              topPadding: 4
              bottomPadding: 4
            }

            Text {
              width: deviceColumn.width
              visible: root.powered && root.sortedDevices.length === 0
              text: root.adapter !== null && root.adapter.discovering
                ? "Scanning for devices…"
                : "No devices found"
              color: "#6d7c8a"
              font.family: Theme.fontFamily
              font.pixelSize: 12
              leftPadding: 8
              topPadding: 4
              bottomPadding: 4
            }

            Repeater {
              model: root.sortedDevices

              PopupRow {
                id: deviceRow
                required property var modelData

                width: deviceColumn.width
                icon: root.deviceIcon(modelData)
                iconColor: modelData.connected
                  ? Theme.accent
                  : (modelData.bonded || modelData.paired
                    ? Theme.foreground
                    : "#6d7c8a")
                title: root.deviceName(modelData)
                subtitle: root.deviceSubtitle(modelData)
                actionText: root.deviceAction(modelData)
                actionPrimary: modelData.connected
                actionEnabled: root.powered
                onClicked: root.activateDevice(modelData)

                Connections {
                  target: deviceRow.modelData

                  function onPairedChanged() {
                    if (deviceRow.modelData.paired
                        && root.pendingPairAddress === deviceRow.modelData.address) {
                      root.pendingPairAddress = "";
                      pairTimer.stop();
                      deviceRow.modelData.connect();
                    }
                  }

                  function onPairingChanged() {
                    if (!deviceRow.modelData.pairing
                        && !deviceRow.modelData.paired
                        && root.pendingPairAddress === deviceRow.modelData.address) {
                      root.pendingPairAddress = "";
                      pairTimer.stop();
                      root.errorText = "Pairing failed.";
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.errorText !== ""
          text: root.errorText
          color: "#b44"
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
