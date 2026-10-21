pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "components"

// Alt+Space application launcher. niri maps the key to
// `qs -c niri ipc call spotlight toggle`, so the overlay itself owns no
// hotkey: opening/closing always goes through the same IPC entry point.
PanelWindow {
  id: root

  property bool opened: false
  property string query: ""
  property int selectedIndex: 0
  property var usage: ({})
  property var results: []
  property var targetScreen: null

  readonly property int rowHeight: 46
  readonly property int maxVisibleRows: 8
  readonly property int visibleRows: Math.max(1, Math.min(results.length, maxVisibleRows))

  // noDisplay entries are helpers (URL handlers, portals, ...) that should not
  // appear in a launcher. Entries without a name cannot be rendered usefully.
  readonly property var allApps: DesktopEntries.applications.values.filter(
    entry => !entry.noDisplay && entry.name.trim() !== ""
  )

  screen: root.targetScreen
  visible: root.opened
  color: "transparent"
  focusable: true
  exclusiveZone: -1
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.opened
    ? WlrKeyboardFocus.Exclusive
    : WlrKeyboardFocus.None

  anchors {
    top: true
    left: true
    right: true
    bottom: true
  }

  function normalize(value) {
    const text = (value === undefined || value === null ? "" : value).toString().toLowerCase();
    // Strip combining accents so "musik" still finds "Musik" and "resume"
    // finds "Résumé", while leaving CJK text untouched.
    return typeof text.normalize === "function"
      ? text.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      : text;
  }

  // Returns a match score, or null when the token is not a subsequence of the
  // candidate. Consecutive characters and word starts are worth more, so
  // "code" ranks "Visual Studio Code" above a scattered match.
  function fuzzyScore(token, candidate) {
    if (token === "")
      return 0;
    if (candidate === "")
      return null;

    let score = 0;
    let cursor = 0;
    let streak = 0;

    for (let i = 0; i < token.length; i++) {
      const found = candidate.indexOf(token[i], cursor);
      if (found === -1)
        return null;

      if (found === cursor)
        streak += 1;
      else
        streak = 0;

      score += 12 + Math.min(streak, 4) * 6;

      if (found === 0
          || candidate[found - 1] === " "
          || candidate[found - 1] === "-"
          || candidate[found - 1] === ".")
        score += 14;

      score -= Math.min(found - cursor, 6) * 2;
      cursor = found + 1;
    }

    // A contiguous occurrence is the strongest signal short of a prefix.
    // Without it, "vim" would rank "Virtual machine viewer" above "Neovim".
    if (candidate === token)
      score += 90;
    else if (candidate.startsWith(token))
      score += 55;
    else if (candidate.indexOf(token) !== -1)
      score += 40;

    // Prefer the shorter of two equally good candidates ("Code" over
    // "Visual Studio Code Insiders" for the query "code"), but never enough
    // to turn a real match into a non-match.
    score -= Math.min(candidate.length, 80) * 0.35;

    return score;
  }

  function scoreEntry(entry, tokens) {
    const name = root.normalize(entry.name);
    const generic = root.normalize(entry.genericName);
    const keywords = root.normalize((entry.keywords || []).join(" "));
    const categories = root.normalize((entry.categories || []).join(" "));
    const comment = root.normalize(entry.comment);
    const id = root.normalize(entry.id);

    // The name carries the most signal; the id and categories exist so
    // "gnome" or "development" still finds something when the visible text
    // does not contain the query.
    const fields = [
      [name, 1],
      [generic, 0.85],
      [keywords, 0.75],
      [id, 0.7],
      [categories, 0.55],
      [comment, 0.55]
    ];

    let total = 0;
    for (let i = 0; i < tokens.length; i++) {
      let best = Number.NEGATIVE_INFINITY;
      for (let j = 0; j < fields.length; j++) {
        const raw = root.fuzzyScore(tokens[i], fields[j][0]);
        if (raw === null)
          continue;
        best = Math.max(best, raw * fields[j][1]);
      }
      if (best === Number.NEGATIVE_INFINITY)
        return Number.NEGATIVE_INFINITY;
      total += best;
    }

    const joined = tokens.join(" ");
    if (name === joined)
      total += 120;
    else if (name.startsWith(joined))
      total += 70;
    else if (name.indexOf(" " + joined) !== -1)
      total += 30;

    // A light history boost breaks ties between equally good matches without
    // letting a frequently used app outrank a clearly better textual match.
    total += Math.min(root.usage[entry.id] || 0, 10) * 4;

    return total;
  }

  function refresh() {
    const text = root.normalize(root.query).trim();
    let entries;

    if (text === "") {
      entries = root.allApps.slice().sort((a, b) => {
        const countA = root.usage[a.id] || 0;
        const countB = root.usage[b.id] || 0;
        if (countA !== countB)
          return countB - countA;
        return a.name.localeCompare(b.name, "en", { sensitivity: "base" });
      });
    } else {
      const tokens = text.split(/\s+/).filter(token => token !== "");
      entries = root.allApps
        .map(entry => ({ entry: entry, score: root.scoreEntry(entry, tokens) }))
        .filter(item => item.score !== Number.NEGATIVE_INFINITY)
        .sort((a, b) => {
          if (b.score !== a.score)
            return b.score - a.score;
          return a.entry.name.localeCompare(b.entry.name, "en", { sensitivity: "base" });
        })
        .map(item => item.entry);
    }

    root.results = entries;
    if (root.selectedIndex >= entries.length)
      root.selectedIndex = Math.max(0, entries.length - 1);
  }

  function selectIndex(index) {
    if (index < 0 || index >= root.results.length)
      return;
    root.selectedIndex = index;
    resultList.positionViewAtIndex(index, ListView.Contain);
  }

  function move(delta) {
    if (root.results.length === 0)
      return;

    // Up/down wrap around; page jumps stop at the ends.
    let next = root.selectedIndex + delta;
    if (next < 0 || next >= root.results.length) {
      if (delta === 1)
        next = 0;
      else if (delta === -1)
        next = root.results.length - 1;
      else
        next = Math.max(0, Math.min(next, root.results.length - 1));
    }
    root.selectIndex(next);
  }

  // Launch on the monitor that currently has the focused niri window. niri
  // only exposes the window's workspace, so resolve output through it; when
  // no window exists fall back to the first screen.
  function pickScreen() {
    const screens = Quickshell.screens;
    const window = Niri.focusedWindow;
    if (window) {
      const workspace = Niri.workspaces.find(item => item.id === window.workspace_id);
      if (workspace) {
        const screen = screens.find(item => item.name === workspace.output);
        if (screen)
          return screen;
      }
    }
    return screens.length > 0 ? screens[0] : null;
  }

  function resolveIcon(icon) {
    if (!icon)
      return Quickshell.iconPath("application-x-executable");
    if (icon.startsWith("file://") || icon.startsWith("image://"))
      return icon;
    if (icon.startsWith("/"))
      return "file://" + icon;
    return Quickshell.iconPath(icon, "application-x-executable");
  }

  function remember(entry) {
    if (!entry)
      return;
    const next = Object.assign({}, root.usage);
    next[entry.id] = (next[entry.id] || 0) + 1;
    root.usage = next;
    usageStore.setText(JSON.stringify(next));
  }

  function launchSelected() {
    const entry = root.results[root.selectedIndex];
    if (!entry)
      return;
    root.remember(entry);
    entry.execute();
    root.close();
  }

  function open() {
    root.targetScreen = root.pickScreen();
    root.opened = true;
    root.query = "";
    root.selectedIndex = 0;
    searchInput.text = "";
    root.refresh();
    resultList.positionViewAtBeginning();
    focusTimer.restart();
  }

  function close() {
    root.opened = false;
    root.query = "";
    root.selectedIndex = 0;
    root.results = [];
  }

  function toggle() {
    if (root.opened)
      root.close();
    else
      root.open();
  }

  onAllAppsChanged: root.refresh()

  FileView {
    id: usageStore

    path: Quickshell.statePath("spotlight-usage.json")
    printErrors: false

    onLoaded: {
      try {
        const stored = JSON.parse(usageStore.text());
        if (stored && typeof stored === "object" && !Array.isArray(stored))
          root.usage = stored;
      } catch (error) {
        // A missing or truncated history file only costs the ranking boost.
      }
      root.refresh();
    }
  }

  IpcHandler {
    target: "spotlight"

    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
  }

  // A zero-length timer runs after the layer surface is mapped, which is when
  // the compositor can hand keyboard focus to the text input.
  Timer {
    id: focusTimer
    interval: 0
    repeat: false
    onTriggered: searchInput.forceActiveFocus()
  }

  // Dim the desktop so the panel reads as a modal surface. Clicking anywhere
  // outside the panel closes the launcher.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.26)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.close()
      onWheel: event => event.accepted = true
    }
  }

  Rectangle {
    id: panel

    width: Math.min(660, root.width - 32)
    height: content.implicitHeight
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(
      Theme.barHeight + 16,
      Math.min(
        Math.round(root.height * 0.16),
        root.height - height - 24
      )
    )
    radius: 14
    color: Theme.background
    border.width: 1
    border.color: Theme.accent

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: {}
      onWheel: event => event.accepted = true
    }

    Column {
      id: content

      width: parent.width
      spacing: 0

      Item {
        width: parent.width
        height: 58

        RowLayout {
          anchors {
            fill: parent
            leftMargin: 16
            rightMargin: 16
          }
          spacing: 12

          Text {
            text: "\uf002"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: 18
            textFormat: Text.PlainText
          }

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            TextInput {
              id: searchInput

              anchors.fill: parent
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.foreground
              selectionColor: Theme.accent
              selectedTextColor: Theme.accentText
              font.family: Theme.fontFamily
              font.pixelSize: 17
              clip: true

              onTextChanged: {
                root.query = text;
                root.selectedIndex = 0;
                root.refresh();
                resultList.positionViewAtBeginning();
              }
              onAccepted: root.launchSelected()

              Keys.onPressed: event => {
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

                switch (event.key) {
                case Qt.Key_Down:
                case Qt.Key_Tab:
                  root.move(shift ? -1 : 1);
                  event.accepted = true;
                  break;
                case Qt.Key_Backtab:
                  root.move(-1);
                  event.accepted = true;
                  break;
                case Qt.Key_Up:
                  root.move(-1);
                  event.accepted = true;
                  break;
                case Qt.Key_PageDown:
                  root.move(root.maxVisibleRows);
                  event.accepted = true;
                  break;
                case Qt.Key_PageUp:
                  root.move(-root.maxVisibleRows);
                  event.accepted = true;
                  break;
                case Qt.Key_Escape:
                  root.close();
                  event.accepted = true;
                  break;
                default:
                  if (ctrl && event.key === Qt.Key_N) {
                    root.move(1);
                    event.accepted = true;
                  } else if (ctrl && event.key === Qt.Key_P) {
                    root.move(-1);
                    event.accepted = true;
                  }
                  break;
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Search applications…"
              visible: searchInput.text === ""
              enabled: false
              color: Theme.textMuted
              font.family: Theme.fontFamily
              font.pixelSize: 17
              textFormat: Text.PlainText
            }
          }

          Text {
            text: "Alt+Space"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Theme.divider
      }

      Item {
        width: parent.width
        height: root.visibleRows * root.rowHeight

        ListView {
          id: resultList

          anchors.fill: parent
          topMargin: 4
          bottomMargin: 4
          model: root.results
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: root.results.length > root.maxVisibleRows

          delegate: Item {
            id: row

            required property var modelData
            required property int index

            width: ListView.view.width
            height: root.rowHeight

            readonly property bool selected: index === root.selectedIndex
            readonly property string subtitle: row.modelData.comment !== ""
              ? row.modelData.comment
              : row.modelData.genericName

            Rectangle {
              anchors {
                fill: parent
                leftMargin: 6
                rightMargin: 6
                topMargin: 2
                bottomMargin: 2
              }
              radius: 8
              color: row.selected
                ? Theme.accent
                : (mouse.containsMouse ? Theme.rowHover : "transparent")
            }

            MouseArea {
              id: mouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              onClicked: {
                root.selectedIndex = index;
                root.launchSelected();
              }
            }

            RowLayout {
              anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 16
              }
              spacing: 12

              IconImage {
                implicitSize: 24
                source: root.resolveIcon(row.modelData.icon)
                visible: status !== Image.Error
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: row.modelData.name
                  color: row.selected ? Theme.accentText : Theme.foreground
                  font.family: Theme.fontFamily
                  font.pixelSize: 13
                  font.bold: true
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }

                Text {
                  Layout.fillWidth: true
                  visible: text !== ""
                  text: row.subtitle
                  color: row.selected
                    ? Theme.accentText
                    : Theme.textSecondary
                  opacity: row.selected ? 0.8 : 1
                  font.family: Theme.fontFamily
                  font.pixelSize: 10
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.results.length === 0
          text: root.query.trim() === ""
            ? "No applications found"
            : "No matches for \"" + root.query.trim() + "\""
          color: Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: 12
          textFormat: Text.PlainText
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Theme.divider
      }

      Item {
        width: parent.width
        height: 34

        RowLayout {
          anchors {
            fill: parent
            leftMargin: 16
            rightMargin: 16
          }
          spacing: 8

          Text {
            Layout.fillWidth: true
            text: root.results.length + (root.results.length === 1 ? " app" : " apps")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }

          Text {
            text: "↑↓ navigate · Enter launch · Esc close"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
