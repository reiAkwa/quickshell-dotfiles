pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import "../components"

Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":network"
  readonly property bool panelOpen: Popout.current === popupKey

  readonly property var device: {
    const devices = Networking.devices.values;
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].connected)
        return devices[i];
    }
    return null;
  }

  readonly property var wifiDevice: {
    const devices = Networking.devices.values;
    for (let i = 0; i < devices.length; i++) {
      if (devices[i].type === DeviceType.Wifi)
        return devices[i];
    }
    return null;
  }

  readonly property var wiredDevices: Networking.devices.values.filter(
    device => device.type === DeviceType.Wired
  )

  readonly property var wifiNetworks: wifiDevice ? wifiDevice.networks.values : []
  property var sortedWifiNetworks: []

  readonly property string mode: {
    if (!device)
      return "disconnected";
    return device.type === DeviceType.Wifi ? "wifi" : "ethernet";
  }

  property real bandwidthDownBits: 0
  property real lastRxBytes: -1
  property string lastInterface: ""

  property var passwordNetwork: null
  property string passwordText: ""
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

  readonly property string bandwidthText: formatBits(bandwidthDownBits)
  readonly property bool wifiUsable: wifiDevice !== null && Networking.wifiEnabled

  text: {
    if (mode === "disconnected")
      return wifiDevice !== null && !Networking.wifiEnabled ? " Off" : " No Network";
    return " " + bandwidthText;
  }
  leadingIcon: {
    if (mode === "wifi")
      return "\udb82\udd22";
    if (mode === "ethernet")
      return "\udb80\ude00";
    return "\udb82\udd20";
  }
  moduleColor: containsMouse ? Qt.lighter(Theme.network, 1.15) : Theme.network

  onClicked: Popout.toggle(popupKey)

  onDeviceChanged: {
    lastRxBytes = -1;
    lastInterface = "";
    bandwidthDownBits = 0;
  }

  onPanelOpenChanged: {
    errorText = "";
    passwordNetwork = null;
    passwordText = "";
    refreshWifiNetworks();
    syncScanning();
    if (panelOpen)
      updateAnchor();
  }

  onWifiDeviceChanged: {
    refreshWifiNetworks();
    syncScanning();
  }

  onWifiNetworksChanged: refreshWifiNetworks()

  function updateAnchor() {
    anchorRightCache = root.mapToItem(null, root.width, 0).x;
  }

  // Kept imperative so per-network signal updates do not rebuild the whole
  // Repeater model (and reset the list position) every few seconds.
  function refreshWifiNetworks() {
    const list = [...root.wifiNetworks];
    list.sort((a, b) => {
      const connectedA = a.connected ? 1 : 0;
      const connectedB = b.connected ? 1 : 0;
      return (connectedB - connectedA) || (b.signalStrength - a.signalStrength);
    });
    root.sortedWifiNetworks = list;
  }

  Connections {
    target: Networking

    function onWifiEnabledChanged() {
      root.syncScanning();
    }
  }

  function syncScanning() {
    if (!wifiDevice)
      return;
    const shouldScan = panelOpen && Networking.wifiEnabled;
    if (wifiDevice.scannerEnabled !== shouldScan)
      wifiDevice.scannerEnabled = shouldScan;
  }

  function formatBits(bits) {
    if (bits >= 1000000000000)
      return (bits / 1000000000000).toFixed(1) + "tb/s";
    if (bits >= 1000000000)
      return (bits / 1000000000).toFixed(1) + "gb/s";
    if (bits >= 1000000)
      return (bits / 1000000).toFixed(1) + "mb/s";
    if (bits >= 1000)
      return (bits / 1000).toFixed(1) + "kb/s";
    return bits.toFixed(1) + "b/s";
  }

  function isSecure(network) {
    if (!network)
      return false;
    return network.security !== WifiSecurityType.Open
      && network.security !== WifiSecurityType.Owe
      && network.security !== WifiSecurityType.Unknown;
  }

  function securityLabel(network) {
    switch (network.security) {
    case WifiSecurityType.Wpa3SuiteB192:
    case WifiSecurityType.Sae:
      return "WPA3";
    case WifiSecurityType.Wpa2Eap:
    case WifiSecurityType.WpaEap:
      return "Enterprise";
    case WifiSecurityType.Wpa2Psk:
      return "WPA2";
    case WifiSecurityType.WpaPsk:
      return "WPA";
    case WifiSecurityType.StaticWep:
    case WifiSecurityType.DynamicWep:
    case WifiSecurityType.Leap:
      return "WEP";
    case WifiSecurityType.Owe:
    case WifiSecurityType.Open:
      return "Open";
    default:
      return "Secured";
    }
  }

  function networkSubtitle(network) {
    if (!network)
      return "";

    const parts = [];
    if (network.state === ConnectionState.Connecting)
      parts.push("Connecting…");
    else if (network.state === ConnectionState.Disconnecting)
      parts.push("Disconnecting…");
    else if (network.connected)
      parts.push("Connected");
    else if (network.known)
      parts.push("Saved");
    else
      parts.push(securityLabel(network));

    parts.push(Math.round(network.signalStrength * 100) + "%");
    return parts.join(" · ");
  }

  function networkAction(network) {
    if (!network)
      return "";
    if (network.state === ConnectionState.Connecting)
      return "Connecting…";
    if (network.state === ConnectionState.Disconnecting)
      return "Disconnecting…";
    return network.connected ? "Disconnect" : "Connect";
  }

  function wiredSubtitle(wired) {
    if (wired.connected)
      return "Connected";
    if (wired.state === ConnectionState.Connecting)
      return "Connecting…";
    if (wired.state === ConnectionState.Disconnecting)
      return "Disconnecting…";
    return "Disconnected";
  }

  function activateNetwork(network) {
    if (!network || !wifiUsable)
      return;

    errorText = "";

    if (network.connected) {
      network.disconnect();
      return;
    }

    if (network.state === ConnectionState.Connecting
        || network.state === ConnectionState.Disconnecting)
      return;

    if (network.known || !isSecure(network)) {
      network.connect();
      return;
    }

    promptPassword(network);
  }

  function activateWired(wired) {
    if (!wired)
      return;
    if (wired.connected) {
      wired.disconnect();
      return;
    }
    if (wired.network)
      wired.network.connect();
  }

  function promptPassword(network) {
    passwordNetwork = network;
    passwordText = "";
    errorText = "";
    Qt.callLater(() => {
      passwordInput.text = "";
      passwordInput.forceActiveFocus();
    });
  }

  function cancelPassword() {
    passwordNetwork = null;
    passwordText = "";
    Qt.callLater(() => panelContent.forceActiveFocus());
  }

  function submitPassword() {
    if (!passwordNetwork || passwordText.length === 0)
      return;
    passwordNetwork.connectWithPsk(passwordText);
    passwordNetwork = null;
    passwordText = "";
    Qt.callLater(() => panelContent.forceActiveFocus());
  }

  function rescanWifi() {
    if (!wifiDevice || !Networking.wifiEnabled)
      return;
    wifiDevice.scannerEnabled = false;
    rescanTimer.restart();
  }

  function updateBandwidth(text) {
    if (!device) {
      bandwidthDownBits = 0;
      lastRxBytes = -1;
      return;
    }

    const name = device.name;
    if (name !== lastInterface) {
      lastInterface = name;
      lastRxBytes = -1;
    }

    let rxBytes = -1;
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      const separator = line.indexOf(":");
      if (separator === -1 || line.slice(0, separator) !== name)
        continue;
      const fields = line.slice(separator + 1).trim().split(/\s+/);
      rxBytes = Number(fields[0]);
      break;
    }

    if (rxBytes < 0)
      return;

    if (lastRxBytes >= 0 && rxBytes >= lastRxBytes)
      bandwidthDownBits = (rxBytes - lastRxBytes) * 8 / 5;
    lastRxBytes = rxBytes;
  }

  Process {
    id: networkProcess
    command: ["cat", "/proc/net/dev"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBandwidth(text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: networkProcess.running = true
  }

  Timer {
    id: rescanTimer
    interval: 100
    onTriggered: {
      if (root.wifiDevice && root.panelOpen && Networking.wifiEnabled)
        root.wifiDevice.scannerEnabled = true;
    }
  }

  Timer {
    interval: 500
    running: root.panelOpen
    repeat: true
    onTriggered: root.updateAnchor()
  }

  // A layer-shell panel is used instead of PopupWindow because the bar itself
  // is a layer-shell surface. Qt cannot create a grabbing xdg_popup for it,
  // which would leave the password field without keyboard input.
  PanelWindow {
    id: panel

    screen: root.targetScreen

    // surfaceShown outlives panelOpen for the exit transition, and cardShown
    // starts one frame after the surface is mapped so the entrance is never
    // consumed while the layer surface is still unmapped.
    property bool surfaceShown: false
    property bool cardShown: false

    visible: surfaceShown
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

    Connections {
      target: root
      function onPanelOpenChanged() {
        if (root.panelOpen) {
          closeTimer.stop();
          panel.surfaceShown = true;
          panel.cardShown = false;
          enterTimer.restart();
        } else {
          enterTimer.stop();
          panel.cardShown = false;
          closeTimer.restart();
        }
      }
    }

    Timer {
      id: enterTimer
      interval: 32
      onTriggered: panel.cardShown = true
    }

    // Keep the surface mapped slightly past the exit curve so the last faded
    // frame is presented instead of being torn down mid-animation.
    Timer {
      id: closeTimer
      interval: Theme.motionExit + 20
      onTriggered: panel.surfaceShown = false
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.panelOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: Popout.close(root.popupKey)
      onWheel: event => event.accepted = true
    }

    Rectangle {
      width: 340
      height: panelContent.implicitHeight + 24
      x: Math.max(8, Math.min(root.anchorRightCache - width, parent.width - width - 8))
      y: panel.cardShown ? 4 : -6
      radius: Theme.moduleRadius
      color: Theme.background
      border.width: 1
      border.color: Theme.accent
      opacity: panel.cardShown ? 1 : 0
      scale: panel.cardShown ? 1 : 0.97
      transformOrigin: Item.Top

      Behavior on y {
        NumberAnimation {
          duration: panel.cardShown ? Theme.motionBase : Theme.motionExit
          easing.type: panel.cardShown ? Theme.easeEnter : Theme.easeExit
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: panel.cardShown ? Theme.motionBase : Theme.motionExit
          easing.type: panel.cardShown ? Theme.easeStandard : Theme.easeExit
        }
      }

      Behavior on scale {
        NumberAnimation {
          duration: panel.cardShown ? Theme.motionBase : Theme.motionExit
          easing.type: panel.cardShown ? Theme.easeEnter : Theme.easeExit
        }
      }

      Behavior on height {
        NumberAnimation {
          duration: Theme.motionBase
          easing.type: Theme.easeStandard
        }
      }

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

        Keys.onEscapePressed: {
          if (root.passwordNetwork)
            root.cancelPassword();
          else
            Popout.close(root.popupKey);
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "Network"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          Item {
            Layout.fillWidth: true
          }

          Text {
            text: root.mode === "wifi"
              ? "Wi-Fi"
              : (root.mode === "ethernet" ? "Wired" : "Offline")
            color: root.device ? Theme.accent : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Theme.divider
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 34
          radius: 6
          color: wifiToggleMouse.containsMouse && root.wifiDevice ? Theme.rowHover : "transparent"

          Behavior on color {
            ColorAnimation {
              duration: Theme.motionFast
              easing.type: Theme.easeStandard
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors {
              leftMargin: 6
              rightMargin: 8
            }
            spacing: 8

            Text {
              text: "\uf1eb"
              color: root.wifiUsable ? Theme.accent : Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 16
            }

            Text {
              Layout.fillWidth: true
              text: "Wi-Fi"
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: 13
            }

            Text {
              text: root.wifiDevice === null
                ? "Unavailable"
                : (Networking.wifiEnabled ? "On" : "Off")
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }

            Rectangle {
              Layout.preferredWidth: 32
              Layout.preferredHeight: 18
              radius: 9
              color: Networking.wifiEnabled ? Theme.accent : Theme.inactive

              Behavior on color {
                ColorAnimation {
                  duration: Theme.motionFast
                  easing.type: Theme.easeStandard
                }
              }

              Rectangle {
                width: 14
                height: 14
                radius: 7
                y: 2
                x: Networking.wifiEnabled ? parent.width - width - 2 : 2
                color: Theme.accentText

                Behavior on x {
                  NumberAnimation {
                    duration: Theme.motionBase
                    easing.type: Theme.easeStandard
                  }
                }
              }
            }
          }

          MouseArea {
            id: wifiToggleMouse
            anchors.fill: parent
            enabled: root.wifiDevice !== null
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              root.errorText = "";
              Networking.wifiEnabled = !Networking.wifiEnabled;
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: 24
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: "Wi-Fi networks"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          PopupButton {
            text: "Scan"
            available: root.wifiUsable
            onClicked: root.rescanWifi()
          }
        }

        Flickable {
          id: networkFlick

          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(
            listColumn.implicitHeight,
            root.passwordNetwork ? 170 : 300
          )
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: listColumn
            width: networkFlick.width
            spacing: 2

            Text {
              width: listColumn.width
              visible: root.wifiDevice === null
              text: "No Wi-Fi adapter"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 12
              leftPadding: 8
              topPadding: 4
              bottomPadding: 4
            }

            Text {
              width: listColumn.width
              visible: root.wifiDevice !== null && !Networking.wifiEnabled
              text: "Wi-Fi is off"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 12
              leftPadding: 8
              topPadding: 4
              bottomPadding: 4
            }

            Text {
              width: listColumn.width
              visible: root.wifiUsable
                && root.sortedWifiNetworks.length === 0
              text: "No networks found"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 12
              leftPadding: 8
              topPadding: 4
              bottomPadding: 4
            }

            Repeater {
              model: root.sortedWifiNetworks

              PopupRow {
                id: wifiRow
                required property var modelData

                width: listColumn.width
                icon: "\uf1eb"
                iconColor: modelData.connected ? Theme.accent : Theme.textSecondary
                title: modelData.name
                subtitle: root.networkSubtitle(modelData)
                actionText: root.networkAction(modelData)
                actionPrimary: modelData.connected
                actionEnabled: root.wifiUsable
                onClicked: root.activateNetwork(modelData)

                Connections {
                  target: wifiRow.modelData

                  function onConnectionFailed(reason) {
                    if (reason === ConnectionFailReason.NoSecrets
                        && root.isSecure(wifiRow.modelData)) {
                      root.promptPassword(wifiRow.modelData);
                      root.errorText = "This network needs a password.";
                    } else {
                      root.errorText = "Could not connect to "
                        + wifiRow.modelData.name + " ("
                        + ConnectionFailReason.toString(reason) + ").";
                    }
                  }
                }
              }
            }

            RowLayout {
              width: listColumn.width
              height: 24
              visible: root.wiredDevices.length > 0
              spacing: 8

              Text {
                Layout.fillWidth: true
                text: "Wired"
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
              }
            }

            Repeater {
              model: root.wiredDevices

              PopupRow {
                required property var modelData

                width: listColumn.width
                icon: "\udb80\ude00"
                iconColor: modelData.connected ? Theme.accent : Theme.textSecondary
                title: modelData.name
                subtitle: root.wiredSubtitle(modelData)
                actionText: modelData.connected
                  ? "Disconnect"
                  : (modelData.network ? "Connect" : "")
                actionPrimary: modelData.connected
                actionEnabled: modelData.connected || modelData.network !== null
                onClicked: root.activateWired(modelData)
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.errorText !== ""
          text: root.errorText
          color: Theme.danger
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: root.passwordNetwork ? passwordColumn.implicitHeight + 16 : 0
          visible: root.passwordNetwork !== null
          radius: 6
          color: Theme.rowHover

          ColumnLayout {
            id: passwordColumn

            anchors {
              left: parent.left
              right: parent.right
              top: parent.top
              margins: 8
            }
            spacing: 6

            Text {
              Layout.fillWidth: true
              text: "Password for " + (root.passwordNetwork ? root.passwordNetwork.name : "")
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 28
              radius: 4
              color: Theme.accentText
              border.width: 1
              border.color: passwordInput.activeFocus ? Theme.accent : Theme.divider

              TextInput {
                id: passwordInput
                objectName: "wifiPasswordInput"

                anchors.fill: parent
                anchors {
                  leftMargin: 7
                  rightMargin: 7
                }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 12
                echoMode: TextInput.Password
                passwordCharacter: "•"
                selectionColor: Theme.accent
                selectedTextColor: Theme.background
                onTextChanged: root.passwordText = text

                onAccepted: root.submitPassword()
                onVisibleChanged: {
                  if (visible) {
                    text = "";
                    forceActiveFocus();
                  }
                }

                Keys.onEscapePressed: root.cancelPassword()
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Item {
                Layout.fillWidth: true
              }

              PopupButton {
                text: "Cancel"
                onClicked: root.cancelPassword()
              }

              PopupButton {
                text: "Connect"
                primary: true
                available: root.passwordText.length > 0
                onClicked: root.submitPassword()
              }
            }
          }
        }
      }
    }
  }
}
