import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"

// Clock in the center of the bar. Left click opens the calendar popout;
// right click switches the bar label between time and date.
Module {
  id: root

  property string screenName: ""
  readonly property string popupKey: screenName + ":clock"
  readonly property bool panelOpen: Popout.current === popupKey

  property bool altFormat: false
  property date shownMonth: new Date()
  property real anchorCenterCache: 0

  readonly property date currentDate: systemClock.date
  readonly property string monthLabel: Qt.formatDate(root.shownMonth, "MMMM yyyy")
  readonly property var weekdayLabels: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  readonly property int monthStartOffset: {
    const first = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth(), 1);
    return first.getDay();
  }

  readonly property int daysInMonth: new Date(
    root.shownMonth.getFullYear(),
    root.shownMonth.getMonth() + 1,
    0
  ).getDate()

  readonly property var monthCells: {
    const cells = [];
    for (let i = 0; i < root.monthStartOffset; i++)
      cells.push(0);
    for (let day = 1; day <= root.daysInMonth; day++)
      cells.push(day);
    while (cells.length % 7 !== 0)
      cells.push(0);
    return cells;
  }

  readonly property var targetScreen: {
    const screens = Quickshell.screens;
    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === screenName)
        return screens[i];
    }
    return null;
  }

  function updateAnchor() {
    anchorCenterCache = root.mapToItem(null, root.width / 2, 0).x;
  }

  function shiftMonth(delta) {
    root.shownMonth = new Date(
      root.shownMonth.getFullYear(),
      root.shownMonth.getMonth() + delta,
      1
    );
  }

  function showCurrentMonth() {
    root.shownMonth = new Date(
      root.currentDate.getFullYear(),
      root.currentDate.getMonth(),
      1
    );
  }

  function isToday(day) {
    if (day <= 0
        || root.shownMonth.getFullYear() !== root.currentDate.getFullYear()
        || root.shownMonth.getMonth() !== root.currentDate.getMonth())
      return false;
    return day === root.currentDate.getDate();
  }

  text: Qt.formatDateTime(systemClock.date, altFormat ? "yyyy/MM/dd" : "HH:mm")
  moduleColor: containsMouse ? Qt.lighter(Theme.clock, 1.12) : Theme.clock

  onClicked: Popout.toggle(popupKey)
  onRightClicked: altFormat = !altFormat

  onPanelOpenChanged: {
    if (panelOpen) {
      showCurrentMonth();
      updateAnchor();
    }
  }

  SystemClock {
    id: systemClock
    precision: SystemClock.Minutes
  }

  Timer {
    interval: 500
    running: root.panelOpen
    repeat: true
    onTriggered: root.updateAnchor()
  }

  // The bar is a layer-shell surface, so the calendar uses the same sibling
  // overlay pattern as the audio/network/notification panels.
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
      x: Math.max(
        8,
        Math.min(
          root.anchorCenterCache - width / 2,
          parent.width - width - 8
        )
      )
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
            text: "Calendar"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.bold: true
          }

          Item {
            Layout.fillWidth: true
          }

          Text {
            text: Qt.formatDateTime(root.currentDate, "HH:mm")
            color: "#6d7c8a"
            font.family: Theme.fontFamily
            font.pixelSize: 11
          }

          PopupButton {
            text: "Today"
            onClicked: root.showCurrentMonth()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: "#c9d6e2"
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          PopupButton {
            Layout.preferredWidth: 30
            text: "\uf053"
            onClicked: root.shiftMonth(-1)
          }

          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.monthLabel
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
          }

          PopupButton {
            Layout.preferredWidth: 30
            text: "\uf054"
            onClicked: root.shiftMonth(1)
          }
        }

        Grid {
          id: calendarGrid

          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: implicitWidth
          Layout.preferredHeight: implicitHeight
          columns: 7
          columnSpacing: 0
          rowSpacing: 2

          Repeater {
            model: root.weekdayLabels

            Item {
              id: weekdayCell

              required property string modelData

              width: 40
              height: 22

              Text {
                anchors.centerIn: parent
                text: weekdayCell.modelData
                color: "#6d7c8a"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
              }
            }
          }

          Repeater {
            model: root.monthCells

            Item {
              id: dayCell

              required property int modelData

              width: 40
              height: 32

              Rectangle {
                anchors.centerIn: parent
                width: 28
                height: 28
                radius: 14
                color: root.isToday(dayCell.modelData)
                  ? Theme.accent
                  : "transparent"
              }

              Text {
                anchors.centerIn: parent
                text: dayCell.modelData > 0 ? dayCell.modelData : ""
                color: root.isToday(dayCell.modelData)
                  ? Theme.background
                  : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: root.isToday(dayCell.modelData)
              }
            }
          }
        }
      }
    }
  }
}
