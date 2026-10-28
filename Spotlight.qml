pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "components"

// Application launcher with !command and =calculator modes. niri maps
// Mod+Space/Alt+Space to `qs -c niri ipc call spotlight toggle`, so the
// overlay itself owns no hotkey: opening/closing always goes through IPC.
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
  readonly property int visibleRows: root.mode === "apps"
    ? Math.max(1, Math.min(results.length, maxVisibleRows))
    : 1

  // Leading ! switches to shell-command mode, leading = to the calculator.
  // Anything else is an application search.
  readonly property string trimmedQuery: root.query.trim()
  readonly property string mode: {
    if (root.trimmedQuery.startsWith("!"))
      return "command";
    if (root.trimmedQuery.startsWith("="))
      return "calc";
    return "apps";
  }
  readonly property string commandText: root.mode === "command"
    ? root.trimmedQuery.slice(1).trim()
    : ""
  readonly property string expression: root.mode === "calc"
    ? root.trimmedQuery.slice(1).trim()
    : ""
  readonly property var calc: root.mode === "calc" ? root.evaluate(root.expression) : null
  readonly property bool calcOk: root.calc !== null && root.calc.ok
  readonly property string calcTitle: {
    if (root.calc === null)
      return "";
    if (root.calc.ok)
      return root.formatNumber(root.calc.value);
    return root.calc.empty ? "Type an expression" : "Invalid expression";
  }
  readonly property string calcSubtitle: {
    if (root.calc === null)
      return "";
    if (root.calc.ok)
      return root.expression;
    return root.calc.empty ? "e.g. = (12 + 3) * 4" : root.calc.error;
  }
  readonly property string footerInfo: {
    if (root.mode === "command")
      return "Shell command";
    if (root.mode === "calc")
      return "Calculator";
    if (root.trimmedQuery === "")
      return root.results.length + " apps · ! command · = calculator";
    return root.results.length + (root.results.length === 1 ? " app" : " apps");
  }
  readonly property string footerHint: {
    if (root.mode === "command")
      return root.commandText !== "" ? "Enter run · Esc close" : "Esc close";
    if (root.mode === "calc")
      return root.calcOk ? "Enter copy · Esc close" : "Esc close";
    return "↑↓ navigate · Enter launch · Esc close";
  }

  // noDisplay entries are helpers (URL handlers, portals, ...) that should not
  // appear in a launcher. Entries without a name cannot be rendered usefully.
  readonly property var allApps: DesktopEntries.applications.values.filter(
    entry => !entry.noDisplay && entry.name.trim() !== ""
  )

  // surfaceShown outlives opened for the exit transition, and cardShown
  // starts one frame after the surface is mapped so the entrance is never
  // consumed while the layer surface is still unmapped.
  property bool surfaceShown: false
  property bool cardShown: false

  screen: root.targetScreen
  visible: surfaceShown
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

  function formatNumber(value) {
    if (!Number.isFinite(value))
      return "Not a number";
    if (value === 0)
      return "0";
    if (Number.isInteger(value))
      return String(value);
    // Trim binary floating-point noise: 0.1 + 0.2 should read as 0.3.
    return String(Number(value.toPrecision(12)));
  }

  // Recursive-descent parser for the "=" mode. eval() would let a stray
  // expression run arbitrary JavaScript, so the calculator only understands
  // numbers, + - * / % ^, unary signs and parentheses.
  function evaluate(source) {
    const input = source
      .replace(/×/g, "*")
      .replace(/÷/g, "/")
      .replace(/−/g, "-");
    let index = 0;

    function fail(message) {
      throw new Error(message);
    }

    function skipSpaces() {
      while (index < input.length && /\s/.test(input[index]))
        index++;
    }

    function parseNumber() {
      skipSpaces();
      const match = /^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/.exec(input.slice(index));
      if (!match)
        fail("Expected a number");
      index += match[0].length;
      return Number(match[0]);
    }

    function parsePrimary() {
      skipSpaces();
      if (input[index] === "(") {
        index++;
        const value = parseExpression();
        skipSpaces();
        if (input[index] !== ")")
          fail("Missing )");
        index++;
        return value;
      }
      return parseNumber();
    }

    function parsePower() {
      const base = parsePrimary();
      skipSpaces();
      if (input[index] === "^") {
        index++;
        // Right-associative, and 2^-3 must parse the sign as part of the
        // exponent rather than as a subtraction.
        return Math.pow(base, parseUnary());
      }
      return base;
    }

    function parseUnary() {
      skipSpaces();
      if (input[index] === "+") {
        index++;
        return parseUnary();
      }
      if (input[index] === "-") {
        index++;
        return -parseUnary();
      }
      return parsePower();
    }

    function parseTerm() {
      let value = parseUnary();
      while (true) {
        skipSpaces();
        const op = input[index];
        if (op !== "*" && op !== "/" && op !== "%")
          break;
        index++;
        const rhs = parseUnary();
        if (op === "*") {
          value *= rhs;
        } else if (op === "/") {
          if (rhs === 0)
            fail("Division by zero");
          value /= rhs;
        } else {
          if (rhs === 0)
            fail("Modulo by zero");
          value %= rhs;
        }
      }
      return value;
    }

    function parseExpression() {
      let value = parseTerm();
      while (true) {
        skipSpaces();
        const op = input[index];
        if (op !== "+" && op !== "-")
          break;
        index++;
        const rhs = parseTerm();
        value = op === "+" ? value + rhs : value - rhs;
      }
      return value;
    }

    if (input === "")
      return { ok: false, empty: true, error: "Type an expression" };

    try {
      const value = parseExpression();
      skipSpaces();
      if (index < input.length)
        fail("Unexpected character");
      if (!Number.isFinite(value))
        fail("Result is not a number");
      return { ok: true, value: value };
    } catch (error) {
      return { ok: false, empty: false, error: String(error.message) };
    }
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
    if (root.mode !== "apps") {
      root.results = [];
      root.selectedIndex = 0;
      return;
    }

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

  function runCommand() {
    if (root.commandText === "")
      return;
    // Same shell rofi/niri spawn-sh use, so pipes and redirections work.
    Quickshell.execDetached(["sh", "-c", root.commandText]);
    root.close();
  }

  function copyResult() {
    if (!root.calcOk)
      return;
    Quickshell.clipboardText = root.calcTitle;
    root.close();
  }

  function launchSelected() {
    if (root.mode === "command") {
      root.runCommand();
      return;
    }
    if (root.mode === "calc") {
      root.copyResult();
      return;
    }

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
    // Keep the results while the panel fades out; open() rebuilds them, and
    // clearing now would collapse the card mid-transition.
  }

  onOpenedChanged: {
    if (root.opened) {
      closeTimer.stop();
      root.surfaceShown = true;
      root.cardShown = false;
      enterTimer.restart();
    } else {
      enterTimer.stop();
      root.cardShown = false;
      closeTimer.restart();
    }
  }

  Timer {
    id: enterTimer
    interval: 32
    onTriggered: root.cardShown = true
  }

  // Keep the surface mapped slightly past the exit curve so the last faded
  // frame is presented instead of being torn down mid-animation.
  Timer {
    id: closeTimer
    interval: Theme.motionExit + 20
    onTriggered: root.surfaceShown = false
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
    opacity: root.cardShown ? 1 : 0

    Behavior on opacity {
      NumberAnimation {
        duration: root.cardShown ? Theme.motionBase : Theme.motionExit
        easing.type: root.cardShown ? Theme.easeStandard : Theme.easeExit
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
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
    opacity: root.cardShown ? 1 : 0
    scale: root.cardShown ? 1 : 0.97

    transform: Translate {
      y: root.cardShown ? 0 : -10

      Behavior on y {
        NumberAnimation {
          duration: root.cardShown ? Theme.motionBase : Theme.motionExit
          easing.type: root.cardShown ? Theme.easeEnter : Theme.easeExit
        }
      }
    }

    Behavior on opacity {
      NumberAnimation {
        duration: root.cardShown ? Theme.motionBase : Theme.motionExit
        easing.type: root.cardShown ? Theme.easeStandard : Theme.easeExit
      }
    }

    Behavior on scale {
      NumberAnimation {
        duration: root.cardShown ? Theme.motionBase : Theme.motionExit
        easing.type: root.cardShown ? Theme.easeEnter : Theme.easeExit
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
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
          visible: root.mode === "apps"
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

              Behavior on color {
                ColorAnimation {
                  duration: Theme.motionFast
                  easing.type: Theme.easeStandard
                }
              }
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

        SpotlightAction {
          anchors.fill: parent
          visible: root.mode === "command"
          symbol: "!"
          title: root.commandText !== "" ? root.commandText : "Run a shell command"
          subtitle: root.commandText !== "" ? "Run with sh -c" : "Type a command after !"
          actionText: "Run"
          active: root.commandText !== ""
          onActivated: root.runCommand()
        }

        SpotlightAction {
          anchors.fill: parent
          visible: root.mode === "calc"
          symbol: "="
          title: root.calcTitle
          subtitle: root.calcSubtitle
          actionText: "Copy"
          active: root.calcOk
          activeTitleSize: 16
          inactiveBackground: Theme.surface
          inactiveTitleColor: root.calc !== null && root.calc.empty
            ? Theme.textSecondary
            : Theme.danger
          onActivated: root.copyResult()
        }

        Text {
          anchors.centerIn: parent
          visible: root.mode === "apps" && root.results.length === 0
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
            text: root.footerInfo
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }

          Text {
            text: root.footerHint
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
