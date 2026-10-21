pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"

// Bell in the bar. Left click opens the history popout, right click clears
// every notification. The toast overlay lives in NotificationPopup.qml.
Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":notifications"
  readonly property bool panelOpen: Popout.current === popupKey

  readonly property var items: Notifications.history
  readonly property var targetScreen: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === screenName)
        return screens[i];
    }
    return null;
  }

  property real anchorRightCache: 0
  property double nowMs: Date.now()

  function updateAnchor() {
    anchorRightCache = root.mapToItem(null, root.width, 0).x;
  }

  leadingIcon: Notifications.dnd ? "\udb80\udc9b" : "\udb80\udc9a"
  text: items.length > 0 ? " " + items.length : ""
  textColor: Notifications.dnd ? Theme.dndOnForeground : Theme.foreground
  moduleColor: Notifications.dnd
    ? (containsMouse ? Qt.lighter(Theme.dndOn, 1.12) : Theme.dndOn)
    : (Notifications.unseen > 0
      ? (containsMouse
        ? Qt.lighter(Theme.notificationActive, 1.12)
        : Theme.notificationActive)
      : (containsMouse
        ? Qt.lighter(Theme.notification, 1.12)
        : Theme.notification))

  onClicked: Popout.toggle(popupKey)
  onRightClicked: Notifications.dnd = !Notifications.dnd

  onPanelOpenChanged: {
    if (panelOpen) {
      updateAnchor();
      Notifications.centerOpen = true;
      Notifications.markSeen();
      nowMs = Date.now();
    } else {
      Notifications.centerOpen = false;
    }
  }

  Timer {
    interval: 500
    running: root.panelOpen
    repeat: true
    onTriggered: root.updateAnchor()
  }

  // Refresh the "3m ago" labels while the panel is open.
  Timer {
    interval: 20000
    running: root.panelOpen
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Same overlay pattern as the audio/network panels: the bar is a
  // layer-shell surface, so an xdg_popup cannot be attached to it.
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
    }

    Rectangle {
      width: 360
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
            text: "Notifications"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          Item {
            Layout.fillWidth: true
          }

          PopupButton {
            text: Notifications.dnd ? "DND on" : "DND off"
            primary: Notifications.dnd
            onClicked: Notifications.dnd = !Notifications.dnd
          }

          PopupButton {
            text: "Clear all"
            available: root.items.length > 0
            onClicked: Notifications.clearAll()
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.items.length === 0
          topPadding: 8
          bottomPadding: 8
          text: "No notifications"
          color: "#6d7c8a"
          font.family: Theme.fontFamily
          font.pixelSize: 12
        }

        Flickable {
          id: historyFlick

          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(historyColumn.implicitHeight, 360)
          visible: root.items.length > 0
          contentWidth: width
          contentHeight: historyColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: historyColumn
            width: historyFlick.width
            spacing: 4

            Repeater {
              model: root.items

              Item {
                id: row

                required property var modelData

                width: historyColumn.width
                height: Math.max(54, rowLayout.implicitHeight + 16)

                Rectangle {
                  anchors.fill: parent
                  radius: 6
                  color: rowHover.hovered ? "#e4eef7" : "transparent"
                }

                HoverHandler {
                  id: rowHover
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: Notifications.invokeDefault(row.modelData)
                }

                RowLayout {
                  id: rowLayout

                  anchors {
                    fill: parent
                    leftMargin: 8
                    rightMargin: 6
                    topMargin: 8
                    bottomMargin: 8
                  }
                  spacing: 8

                  Item {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignTop

                    Image {
                      id: rowIcon

                      anchors.fill: parent
                      source: Notifications.displayIcon(row.modelData)
                      visible: source !== "" && status !== Image.Error
                      sourceSize.width: 26
                      sourceSize.height: 26
                      fillMode: Image.PreserveAspectFit
                      smooth: true
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: !rowIcon.visible
                      text: "\uf0f3"
                      color: Theme.accent
                      font.family: Theme.fontFamily
                      font.pixelSize: 15
                      textFormat: Text.PlainText
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: 6

                      Text {
                        Layout.fillWidth: true
                        text: row.modelData.appName !== ""
                          ? row.modelData.appName
                          : "Notification"
                        color: "#6d7c8a"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                      }

                      Text {
                        text: Notifications.timeAgo(row.modelData.id, root.nowMs)
                        color: "#6d7c8a"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        textFormat: Text.PlainText
                      }
                    }

                    Text {
                      Layout.fillWidth: true
                      text: row.modelData.summary
                      color: Theme.foreground
                      font.family: Theme.fontFamily
                      font.pixelSize: 13
                      font.bold: true
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      Layout.fillWidth: true
                      visible: text !== ""
                      text: row.modelData.body
                      color: "#5b6773"
                      font.family: Theme.fontFamily
                      font.pixelSize: 11
                      wrapMode: Text.Wrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Flow {
                      Layout.fillWidth: true
                      Layout.preferredHeight: implicitHeight
                      spacing: 4

                      Repeater {
                        model: row.modelData.actions

                        PopupButton {
                          required property var modelData

                          visible: modelData.identifier !== "default"
                          text: modelData.text
                          maxTextWidth: 110
                          onClicked: {
                            const resident = row.modelData.resident;
                            modelData.invoke();
                            if (!resident)
                              row.modelData.dismiss();
                          }
                        }
                      }
                    }
                  }

                  Text {
                    text: "\uf00d"
                    color: closeMouse.containsMouse ? Theme.foreground : "#9aa7b3"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignTop
                    textFormat: Text.PlainText

                    MouseArea {
                      id: closeMouse
                      anchors.fill: parent
                      anchors.margins: -6
                      hoverEnabled: true
                      onClicked: row.modelData.dismiss()
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
