pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../components"

// Output volume on the bar, plus a mixer popout for the default output,
// per-application playback streams and the default microphone.
Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":audio"
  readonly property bool panelOpen: Popout.current === popupKey

  property var sink: null
  property var source: null
  property real anchorRightCache: 0

  readonly property var audio: sink ? sink.audio : null
  readonly property var micAudio: source ? source.audio : null
  readonly property int volume: audio ? Math.round(audio.volume * 100) : 0
  readonly property bool muted: audio ? audio.muted : false
  readonly property int micVolume: micAudio ? Math.round(micAudio.volume * 100) : 0
  readonly property bool micMuted: micAudio ? micAudio.muted : false

  readonly property var targetScreen: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === screenName)
        return screens[i];
    }
    return null;
  }

  // PwNodeType::Sink and ::Source are single bits; the composite types like
  // AudioOutStream also contain those bits, so combine them with the Stream
  // bit explicitly instead of comparing whole enum values.
  readonly property var sinks: {
    const nodes = Pipewire.nodes.values;
    return nodes.filter(node => node.audio !== null
      && (node.type & PwNodeType.Stream) === 0
      && (node.type & PwNodeType.Sink) !== 0);
  }

  readonly property var sources: {
    const nodes = Pipewire.nodes.values;
    return nodes.filter(node => node.audio !== null
      && (node.type & PwNodeType.Stream) === 0
      && (node.type & PwNodeType.Source) !== 0);
  }

  readonly property var playbackStreams: {
    const nodes = Pipewire.nodes.values;
    const streams = nodes.filter(node => node.audio !== null
      && (node.type & PwNodeType.Stream) !== 0
      && (node.type & PwNodeType.Sink) !== 0);
    // Sort by id so metadata updates do not reorder the list under the cursor.
    streams.sort((a, b) => a.id - b.id);
    return streams;
  }

  readonly property var trackedNodes: {
    const nodes = Pipewire.nodes.values;
    const result = [];
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].audio !== null)
        result.push(nodes[i]);
    }
    return result;
  }

  function refreshAudio() {
    root.sink = Pipewire.defaultAudioSink;
    root.source = Pipewire.defaultAudioSource;
  }

  Component.onCompleted: refreshAudio()

  Connections {
    target: Pipewire

    function onReadyChanged() { root.refreshAudio() }
    function onDefaultAudioSinkChanged() { root.refreshAudio() }
    function onDefaultAudioSourceChanged() { root.refreshAudio() }
  }

  PwObjectTracker {
    objects: root.trackedNodes
  }

  function iconForVolume(value) {
    if (value <= 33)
      return "\uf026";
    if (value <= 66)
      return "\uf027";
    return "\uf028";
  }

  function setVolume(node, value) {
    if (!node || !node.audio)
      return;
    node.audio.volume = Math.max(0, Math.min(1, value));
  }

  function toggleMute(node) {
    if (!node || !node.audio)
      return;
    node.audio.muted = !node.audio.muted;
  }

  function deviceName(node) {
    if (!node)
      return "";
    return node.description || node.nickname || node.name;
  }

  function propertyOf(node, key) {
    if (!node || !node.properties)
      return "";
    return node.properties[key] || "";
  }

  function streamTitle(node) {
    if (!node)
      return "";
    return propertyOf(node, "application.name")
      || node.nickname
      || node.description
      || node.name;
  }

  function streamSubtitle(node) {
    const media = propertyOf(node, "media.title")
      || propertyOf(node, "media.name");
    if (media !== "" && media !== streamTitle(node))
      return media;
    return propertyOf(node, "application.process.binary");
  }

  function streamIcon(node) {
    const identifiers = (propertyOf(node, "application.name") + " "
      + propertyOf(node, "application.icon-name") + " "
      + propertyOf(node, "media.name")).toLowerCase();
    if (identifiers.indexOf("firefox") !== -1)
      return "\uf269";
    if (identifiers.indexOf("chrom") !== -1)
      return "\uf268";
    if (identifiers.indexOf("spotify") !== -1)
      return "\uf1bc";
    if (identifiers.indexOf("discord") !== -1)
      return "\uf392";
    if (identifiers.indexOf("steam") !== -1)
      return "\uf1b6";
    return "\uf001";
  }

  function updateAnchor() {
    anchorRightCache = root.mapToItem(null, root.width, 0).x;
  }

  text: muted ? "" : " " + volume + "%"
  leadingIcon: muted ? "\uf466" : iconForVolume(volume)
  moduleColor: containsMouse ? Qt.lighter(Theme.audio, 1.15) : Theme.audio

  onClicked: Popout.toggle(popupKey)
  onRightClicked: toggleMute(root.sink)
  onScrolled: delta => {
    if (!audio)
      return;
    audio.volume = Math.max(0, Math.min(1.0, audio.volume + delta * 0.01));
  }

  onPanelOpenChanged: {
    if (panelOpen)
      updateAnchor();
  }

  Timer {
    interval: 500
    running: root.panelOpen
    repeat: true
    onTriggered: root.updateAnchor()
  }

  // The bar is a layer-shell surface, so the popout is a sibling overlay
  // instead of an xdg_popup (same reason as the network/bluetooth panels).
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
            text: "Audio"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          Item {
            Layout.fillWidth: true
          }

          Text {
            text: root.sink === null
              ? "Unavailable"
              : (root.muted ? "Muted" : "Output " + root.volume + "%")
            color: root.sink === null
              ? Theme.textSecondary
              : (root.muted ? Theme.danger : Theme.accent)
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Theme.divider
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.muted ? "\uf466" : root.iconForVolume(root.volume)
            color: root.muted ? Theme.danger : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 16
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: root.sink === null ? "No output device" : root.deviceName(root.sink)
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: 13
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Text {
              Layout.fillWidth: true
              text: "Output"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 10
            }
          }

          Text {
            text: root.muted ? "Muted" : root.volume + "%"
            color: root.muted ? Theme.textMuted : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          PopupButton {
            Layout.preferredWidth: 30
            text: root.muted ? "\uf466" : "\uf028"
            primary: root.muted
            available: root.audio !== null
            onClicked: root.toggleMute(root.sink)
          }
        }

        VolumeSlider {
          Layout.fillWidth: true
          Layout.preferredHeight: implicitHeight
          value: root.audio ? root.audio.volume : 0
          muted: root.muted
          interactive: root.audio !== null
          onMoved: value => root.setVolume(root.sink, value)
        }

        Flow {
          Layout.fillWidth: true
          Layout.preferredHeight: implicitHeight
          visible: root.sinks.length > 1
          spacing: 6

          Repeater {
            model: root.sinks

            PopupButton {
              required property var modelData

              text: root.deviceName(modelData)
              maxTextWidth: 130
              primary: modelData === root.sink
              onClicked: Pipewire.preferredDefaultAudioSink = modelData
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
          Layout.preferredHeight: 18
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: "APPLICATIONS"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            text: root.playbackStreams.length
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }
        }

        Flickable {
          id: appsFlick

          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(appsColumn.implicitHeight, 220)
          contentWidth: width
          contentHeight: appsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: appsColumn
            width: appsFlick.width
            spacing: 2

            Text {
              width: appsColumn.width
              visible: root.playbackStreams.length === 0
              text: "No applications playing audio"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 12
              leftPadding: 8
              topPadding: 4
              bottomPadding: 4
            }

            Repeater {
              model: root.playbackStreams

              Item {
                id: streamRow
                required property var modelData

                width: appsColumn.width
                height: 54

                Rectangle {
                  anchors.fill: parent
                  radius: 6
                  color: streamHover.hovered ? Theme.rowHover : "transparent"
                }

                HoverHandler {
                  id: streamHover
                }

                RowLayout {
                  anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                  }
                  height: 26
                  spacing: 8

                  Text {
                    Layout.preferredWidth: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: root.streamIcon(streamRow.modelData)
                    color: streamRow.modelData.audio.muted
                      ? Theme.textMuted
                      : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      Layout.fillWidth: true
                      text: root.streamTitle(streamRow.modelData)
                      color: Theme.foreground
                      font.family: Theme.fontFamily
                      font.pixelSize: 13
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      Layout.fillWidth: true
                      text: root.streamSubtitle(streamRow.modelData)
                      visible: text !== ""
                      color: Theme.textSecondary
                      font.family: Theme.fontFamily
                      font.pixelSize: 10
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }
                  }

                  Text {
                    text: streamRow.modelData.audio.muted
                      ? "Muted"
                      : Math.round(streamRow.modelData.audio.volume * 100) + "%"
                    color: streamRow.modelData.audio.muted
                      ? Theme.textMuted
                      : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                  }

                  PopupButton {
                    Layout.preferredWidth: 30
                    text: streamRow.modelData.audio.muted ? "\uf466" : "\uf028"
                    primary: streamRow.modelData.audio.muted
                    onClicked: root.toggleMute(streamRow.modelData)
                  }
                }

                VolumeSlider {
                  anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 3
                  }
                  height: 18
                  value: streamRow.modelData.audio.volume
                  muted: streamRow.modelData.audio.muted
                  onMoved: value => root.setVolume(streamRow.modelData, value)
                }
              }
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
          spacing: 8

          Text {
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.micMuted ? "\uf131" : "\uf130"
            color: root.micMuted ? Theme.danger : Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 16
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: root.source === null
                ? "No microphone"
                : root.deviceName(root.source)
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: 13
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Text {
              Layout.fillWidth: true
              text: "Microphone"
              color: Theme.textSecondary
              font.family: Theme.fontFamily
              font.pixelSize: 10
            }
          }

          Text {
            text: root.micMuted ? "Muted" : root.micVolume + "%"
            color: root.micMuted ? Theme.textMuted : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          PopupButton {
            Layout.preferredWidth: 30
            text: root.micMuted ? "\uf131" : "\uf130"
            primary: root.micMuted
            available: root.micAudio !== null
            onClicked: root.toggleMute(root.source)
          }
        }

        VolumeSlider {
          Layout.fillWidth: true
          Layout.preferredHeight: implicitHeight
          value: root.micAudio ? root.micAudio.volume : 0
          muted: root.micMuted
          interactive: root.micAudio !== null
          onMoved: value => root.setVolume(root.source, value)
        }

        Flow {
          Layout.fillWidth: true
          Layout.preferredHeight: implicitHeight
          visible: root.sources.length > 1
          spacing: 6

          Repeater {
            model: root.sources

            PopupButton {
              required property var modelData

              text: root.deviceName(modelData)
              maxTextWidth: 130
              primary: modelData === root.source
              onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
          }
        }
      }
    }
  }
}
