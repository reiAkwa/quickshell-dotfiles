pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

// One toast in NotificationPopup.qml. Hovering pauses the auto-expire timer,
// clicking the card invokes the client's default action (if any).
Rectangle {
  id: root

  required property var notification

  signal closed

  readonly property color urgencyColor: {
    if (!notification)
      return Theme.accent;
    switch (notification.urgency) {
    case NotificationUrgency.Critical:
      return Theme.alert;
    case NotificationUrgency.Low:
      return Theme.textMuted;
    default:
      return Theme.accent;
    }
  }

  // image-path is often the application icon (notify-send -i does this),
  // so it is only used as a fallback for the small icon, never as a preview.
  readonly property string appIconSource: Notifications.displayIcon(notification)

  width: parent ? parent.width : 360
  // The card collapses after it fades so the remaining toasts glide up
  // instead of jumping when the model row disappears.
  implicitHeight: closing ? 0 : layout.implicitHeight + 20
  radius: Theme.moduleRadius
  color: Theme.background
  border.width: 1
  border.color: urgencyColor
  clip: true

  property bool shown: false
  property bool closing: false

  opacity: shown && !closing ? 1 : 0
  scale: shown && !closing ? 1 : 0.98
  transformOrigin: Item.Top

  transform: Translate {
    y: root.shown && !root.closing ? 0 : -8

    Behavior on y {
      NumberAnimation {
        duration: root.closing ? Theme.motionExit : Theme.motionBase
        easing.type: root.closing ? Theme.easeExit : Theme.easeEnter
      }
    }
  }

  Behavior on opacity {
    NumberAnimation {
      duration: root.closing ? Theme.motionExit : Theme.motionBase
      easing.type: root.closing ? Theme.easeExit : Theme.easeStandard
    }
  }

  Behavior on scale {
    NumberAnimation {
      duration: root.closing ? Theme.motionExit : Theme.motionBase
      easing.type: root.closing ? Theme.easeExit : Theme.easeEnter
    }
  }

  Behavior on implicitHeight {
    NumberAnimation {
      duration: root.closing ? Theme.motionExit : Theme.motionBase
      easing.type: root.closing ? Theme.easeExit : Theme.easeEnter
    }
  }

  function beginClose() {
    if (root.closing)
      return;
    root.closing = true;
    closeTimer.restart();
  }

  Timer {
    id: closeTimer
    interval: Theme.motionExit + 16
    onTriggered: root.closed()
  }

  // The toast surface is mapped together with the first card; delay the
  // entrance one frame so the fade is not consumed while still unmapped.
  Timer {
    id: enterTimer
    interval: 32
    running: true
    onTriggered: root.shown = true
  }

  HoverHandler {
    id: hover
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      Notifications.invokeDefault(root.notification);
      root.beginClose();
    }
  }

  RowLayout {
    id: layout

    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: 10
    }
    spacing: 10

    Item {
      Layout.preferredWidth: 34
      Layout.preferredHeight: 34
      Layout.alignment: Qt.AlignTop

      Image {
        id: appIcon
        anchors.fill: parent
        source: root.appIconSource
        visible: source !== "" && status !== Image.Error
        sourceSize.width: 34
        sourceSize.height: 34
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      Text {
        anchors.centerIn: parent
        visible: !appIcon.visible
        text: "\uf0f3"
        color: root.urgencyColor
        font.family: Theme.fontFamily
        font.pixelSize: 18
        textFormat: Text.PlainText
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: root.notification.appName !== ""
            ? root.notification.appName
            : "Notification"
          color: Theme.textSecondary
          font.family: Theme.fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          text: "\uf00d"
          color: closeMouse.containsMouse ? Theme.foreground : Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: 11
          textFormat: Text.PlainText

          Behavior on color {
            ColorAnimation {
              duration: Theme.motionFast
              easing.type: Theme.easeStandard
            }
          }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            onClicked: root.beginClose()
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.notification.summary
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
        text: root.notification.body
        color: Theme.textStrong
        font.family: Theme.fontFamily
        font.pixelSize: 12
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: 6

        Repeater {
          model: root.notification.actions

          PopupButton {
            required property var modelData

            visible: modelData.identifier !== "default"
            text: modelData.text
            maxTextWidth: 120
            onClicked: {
              const resident = root.notification.resident;
              modelData.invoke();
              if (!resident)
                root.closed();
            }
          }
        }
      }
    }
  }

  Timer {
    interval: Notifications.timeoutMs(root.notification)
    running: interval > 0 && !hover.hovered && !root.closing
    onTriggered: root.beginClose()
  }
}
