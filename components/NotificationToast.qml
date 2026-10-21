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
  implicitHeight: layout.implicitHeight + 20
  radius: Theme.moduleRadius
  color: Theme.background
  border.width: 1
  border.color: urgencyColor
  opacity: 0

  Behavior on opacity {
    NumberAnimation {
      duration: 120
    }
  }

  Component.onCompleted: opacity = 1

  HoverHandler {
    id: hover
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      Notifications.invokeDefault(root.notification);
      root.closed();
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

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            onClicked: root.closed()
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
    running: interval > 0 && !hover.hovered
    onTriggered: root.closed()
  }
}
