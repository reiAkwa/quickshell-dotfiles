pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "components"

// Clipboard history picker backed by cliphist. The storage side stays in
// `wl-paste --watch cliphist store`; this overlay only lists, previews,
// copies and deletes entries. niri maps Mod+V to
// `qs -c niri ipc call clipboard toggle`.
PanelWindow {
  id: root

  property bool opened: false
  property string query: ""
  property int selectedIndex: 0
  property var entries: []
  property var results: []
  property var targetScreen: null
  property string listError: ""

  // Set by reload() so the next list parse can keep the current row after a
  // delete instead of jumping back to the newest entry.
  property int pendingIndex: -1

  // Thumbnails are decoded one at a time into the shell cache and kept for
  // this process. previewCache holds at most 8 KiB per text entry.
  property var thumbCache: ({})
  property var thumbQueue: []
  property string thumbId: ""
  property string thumbPath: ""
  property var previewCache: ({})
  property string previewId: ""
  property string previewRunningId: ""
  property string previewError: ""

  readonly property int rowHeight: 52
  readonly property int maxVisibleRows: 9
  readonly property int panelTop: Math.max(Theme.barHeight + 16, Math.round(root.height * 0.1))
  readonly property int panelHeight: Math.max(320, Math.min(560, root.height - root.panelTop - 24))
  readonly property var selectedEntry: root.results[root.selectedIndex] || null
  readonly property var selectedThumb: root.selectedEntry
    ? root.thumbCache[root.selectedEntry.id]
    : null
  readonly property bool selectedHasThumb: root.selectedThumb !== null
    && root.selectedThumb !== undefined
    && root.selectedThumb.source !== ""
  readonly property bool selectedPreviewLoaded: root.selectedEntry !== null
    && root.previewCache[root.selectedEntry.id] !== undefined
  readonly property string selectedPreviewText: root.selectedPreviewLoaded
    ? root.previewCache[root.selectedEntry.id]
    : ""
  readonly property string selectedBadge: {
    const entry = root.selectedEntry;
    if (!entry)
      return "";
    if (entry.image)
      return entry.format.toUpperCase()
        + (entry.dimensions !== "" ? " · " + entry.dimensions : "");
    if (entry.binary)
      return "BINARY";
    return "TEXT";
  }
  readonly property string footerInfo: {
    if (root.listError !== "")
      return root.listError;
    if (root.entries.length === 0)
      return "No clipboard history";
    if (root.query.trim() === "")
      return root.entries.length + (root.entries.length === 1 ? " item" : " items");
    return root.results.length + " of " + root.entries.length + " items";
  }
  readonly property string emptyMessage: {
    if (root.listError !== "")
      return root.listError;
    if (root.entries.length === 0)
      return "Clipboard history is empty";
    return "No matches for \"" + root.query.trim() + "\"";
  }

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
    return typeof text.normalize === "function"
      ? text.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      : text;
  }

  function shellQuote(value) {
    return "'" + value.replace(/'/g, "'\\''") + "'";
  }

  function imageExtension(format) {
    switch (format) {
    case "png":
      return "png";
    case "jpeg":
    case "jpg":
      return "jpg";
    case "webp":
      return "webp";
    case "gif":
      return "gif";
    case "bmp":
      return "bmp";
    case "ico":
      return "ico";
    case "tif":
    case "tiff":
      return "tiff";
    default:
      return "";
    }
  }

  // A cliphist list line is "<id>\t<preview>". Text previews have newlines and
  // tabs replaced by spaces; images use the marker
  // "[[ binary data <size> <format> <width>x<height> ]]".
  function parseLine(line) {
    const separator = line.indexOf("\t");
    if (separator <= 0)
      return null;

    const id = line.slice(0, separator).trim();
    if (!/^\d+$/.test(id))
      return null;

    const preview = line.slice(separator + 1);
    const entry = {
      id: id,
      preview: preview,
      searchText: root.normalize(preview),
      binary: false,
      image: false,
      format: "",
      extension: "",
      dimensions: "",
      size: ""
    };

    if (preview.startsWith("[[ binary data")) {
      entry.binary = true;
      const match = /^\[\[\s*binary data\s+(.+?)\s*\]\]$/.exec(preview);
      if (match) {
        const info = match[1];
        const tokens = info.split(/\s+/);
        let dimsIndex = -1;
        for (let i = 0; i < tokens.length; i++) {
          if (/^\d+x\d+$/.test(tokens[i])) {
            dimsIndex = i;
            break;
          }
        }

        if (dimsIndex >= 0) {
          entry.dimensions = tokens[dimsIndex];
          entry.size = tokens.slice(0, Math.max(0, dimsIndex - 1)).join(" ");
          if (dimsIndex > 0)
            entry.format = tokens[dimsIndex - 1].toLowerCase();
        } else if (tokens.length > 0) {
          entry.format = tokens[tokens.length - 1].toLowerCase();
          entry.size = tokens.slice(0, tokens.length - 1).join(" ");
        }

        entry.extension = root.imageExtension(entry.format);
        entry.image = entry.extension !== "";
      }
    }

    return entry;
  }

  function tokens() {
    const text = root.normalize(root.query).trim();
    return text === "" ? [] : text.split(/\s+/).filter(token => token !== "");
  }

  function filterEntries(list, words) {
    if (words.length === 0)
      return list.slice();

    const matches = [];
    for (let i = 0; i < list.length; i++) {
      const entry = list[i];
      let score = 0;
      let ok = true;
      for (let j = 0; j < words.length; j++) {
        const word = words[j];
        const at = entry.searchText.indexOf(word);
        if (at === -1) {
          ok = false;
          break;
        }
        // Prefer whole-word and prefix hits, but keep cliphist's newest-first
        // order for equal scores.
        if (at === 0)
          score += 60;
        else if (/[\s,;:/\\|([{'"\-]/.test(entry.searchText[at - 1]))
          score += 40;
        else
          score += 20;
      }
      if (ok) {
        if (words.length === 1 && entry.searchText === words[0])
          score += 100;
        matches.push({ entry: entry, score: score, index: i });
      }
    }

    matches.sort((a, b) => {
      if (b.score !== a.score)
        return b.score - a.score;
      return a.index - b.index;
    });

    return matches.map(item => item.entry);
  }

  function rebuild(resetSelection) {
    const list = root.filterEntries(root.entries, root.tokens());
    root.results = list;
    if (resetSelection)
      root.selectedIndex = 0;
    else
      root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, list.length - 1));
    if (root.opened)
      resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
  }

  function reload(index) {
    root.pendingIndex = index;
    root.listError = "";
    listProcess.running = true;
  }

  function applyList(text) {
    const lines = text.split("\n");
    const parsed = [];
    for (let i = 0; i < lines.length; i++) {
      const entry = root.parseLine(lines[i]);
      if (entry)
        parsed.push(entry);
    }

    root.entries = parsed;
    root.results = root.filterEntries(parsed, root.tokens());
    const target = root.pendingIndex >= 0 ? root.pendingIndex : 0;
    root.selectedIndex = Math.max(0, Math.min(target, root.results.length - 1));
    root.pendingIndex = -1;

    if (root.opened) {
      Qt.callLater(() => resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain));
    }
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

  // Same screen resolution as Spotlight: use the output of niri's focused
  // window, falling back to the first monitor.
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

  function rowTitle(entry) {
    if (entry.image)
      return entry.format.toUpperCase() + " image";
    if (entry.binary)
      return "Binary data";
    return entry.preview;
  }

  function rowSubtitle(entry) {
    if (entry.image) {
      const parts = [];
      if (entry.size !== "")
        parts.push(entry.size);
      parts.push(entry.format.toUpperCase());
      if (entry.dimensions !== "")
        parts.push(entry.dimensions);
      return parts.join(" · ");
    }
    if (entry.binary) {
      return entry.preview
        .replace(/^\[\[\s*binary data\s*/, "")
        .replace(/\s*\]\]$/, "");
    }
    const truncated = entry.preview.endsWith("…");
    return "Text · " + entry.preview.length + (truncated ? "+" : "") + " chars";
  }

  function thumbSource(id) {
    const item = root.thumbCache[id];
    return item && item.source ? item.source : "";
  }

  function hasThumbFailed(id) {
    const item = root.thumbCache[id];
    return item !== undefined && item !== null && item.failed === true;
  }

  function cacheThumb(id, source, failed) {
    const next = Object.assign({}, root.thumbCache);
    next[id] = { source: source, failed: failed };
    root.thumbCache = next;
  }

  function thumbQueued(id) {
    const queue = root.thumbQueue;
    for (let i = 0; i < queue.length; i++) {
      if (queue[i].id === id)
        return true;
    }
    return false;
  }

  function requestThumb(entry) {
    if (!entry || !entry.image)
      return;
    if (root.thumbCache[entry.id] !== undefined)
      return;
    if (root.thumbQueued(entry.id))
      return;
    root.thumbQueue = root.thumbQueue.concat([entry]);
    root.pumpThumbs();
  }

  function pumpThumbs() {
    if (thumbProcess.running || root.thumbQueue.length === 0)
      return;

    const entry = root.thumbQueue[0];
    root.thumbQueue = root.thumbQueue.slice(1);
    root.thumbId = entry.id;
    root.thumbPath = Quickshell.cachePath(
      "clipboard-" + entry.id + "." + entry.extension
    );
    thumbProcess.running = true;
  }

  function cachePreview(id, text) {
    const next = Object.assign({}, root.previewCache);
    next[id] = text;
    const keys = Object.keys(next);
    if (keys.length > 40) {
      const trimmed = {};
      for (let i = keys.length - 40; i < keys.length; i++)
        trimmed[keys[i]] = next[keys[i]];
      root.previewCache = trimmed;
    } else {
      root.previewCache = next;
    }
  }

  function requestPreview() {
    if (root.opened)
      previewTimer.restart();
  }

  function fetchPreview() {
    if (!root.opened)
      return;
    const entry = root.selectedEntry;
    if (!entry || entry.binary || root.previewCache[entry.id] !== undefined) {
      root.previewId = "";
      root.previewError = "";
      return;
    }

    root.previewId = entry.id;
    root.previewError = "";
    root.startPreviewIfIdle();
  }

  // One decode at a time. If the selection moved while a decode was running,
  // its output is ignored and the newest selection starts when it exits.
  function startPreviewIfIdle() {
    if (previewProcess.running || root.previewId === "")
      return;
    if (root.previewCache[root.previewId] !== undefined)
      return;
    root.previewRunningId = root.previewId;
    previewProcess.running = true;
  }

  function forget(id) {
    root.thumbQueue = root.thumbQueue.filter(item => item.id !== id);
    if (root.thumbCache[id] !== undefined) {
      const thumbs = Object.assign({}, root.thumbCache);
      delete thumbs[id];
      root.thumbCache = thumbs;
    }
    if (root.previewCache[id] !== undefined) {
      const previews = Object.assign({}, root.previewCache);
      delete previews[id];
      root.previewCache = previews;
    }
  }

  function copyEntry(entry) {
    if (!entry)
      return;
    root.copyId = entry.id;
    copyProcess.running = true;
  }

  function copySelected() {
    root.copyEntry(root.selectedEntry);
  }

  function removeAt(index) {
    if (index < 0 || index >= root.results.length)
      return;
    const entry = root.results[index];
    root.deleteId = entry.id;
    root.deleteIndex = index;
    deleteProcess.running = true;
  }

  function removeSelected() {
    root.removeAt(root.selectedIndex);
  }

  function open() {
    root.targetScreen = root.pickScreen();
    root.opened = true;
    root.query = "";
    root.selectedIndex = 0;
    searchInput.text = "";
    root.pendingIndex = -1;
    root.rebuild(true);
    root.reload(-1);
    cleanupProcess.running = true;
    focusTimer.restart();
    previewTimer.restart();
  }

  function close() {
    root.opened = false;
    root.query = "";
    root.pendingIndex = -1;
    root.previewId = "";
    searchInput.text = "";
    root.selectedIndex = 0;
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

  property string copyId: ""
  property string deleteId: ""
  property int deleteIndex: 0

  IpcHandler {
    target: "clipboard"

    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
  }

  onSelectedEntryChanged: {
    root.previewError = "";
    root.requestPreview();
  }

  Process {
    id: listProcess

    command: ["cliphist", "-preview-width", "400", "list"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyList(text)
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.entries = [];
        root.results = [];
        root.selectedIndex = 0;
        root.listError = "cliphist list failed (exit " + exitCode + ")";
      }
    }
  }

  Process {
    id: copyProcess

    command: ["sh", "-c", "cliphist decode " + root.copyId + " | wl-copy"]
    onExited: function(exitCode) { root.close() }
  }

  Process {
    id: deleteProcess

    command: ["sh", "-c", "printf '%s\\tx\\n' " + root.deleteId + " | cliphist delete"]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.forget(root.deleteId);
        root.reload(root.deleteIndex);
      } else {
        root.listError = "cliphist delete failed (exit " + exitCode + ")";
      }
    }
  }

  Process {
    id: thumbProcess

    command: [
      "sh",
      "-c",
      "cliphist decode " + root.thumbId + " > " + root.shellQuote(root.thumbPath)
    ]

    onExited: function(exitCode) {
      if (exitCode === 0)
        root.cacheThumb(root.thumbId, "file://" + root.thumbPath, false);
      else
        root.cacheThumb(root.thumbId, "", true);
      root.pumpThumbs();
    }
  }

  Process {
    id: previewProcess

    command: [
      "sh",
      "-c",
      "cliphist decode " + root.previewRunningId + " | head -c 8192"
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.previewRunningId === "" || root.previewRunningId !== root.previewId)
          return;
        if (!root.selectedEntry || root.selectedEntry.id !== root.previewRunningId)
          return;
        if (root.selectedEntry.binary)
          return;
        root.cachePreview(root.previewRunningId, text);
      }
    }

    onExited: function(exitCode) {
      const finishedId = root.previewRunningId;
      root.previewRunningId = "";
      if (finishedId === root.previewId) {
        if (exitCode !== 0)
          root.previewError = "Preview failed (exit " + exitCode + ")";
        root.previewId = "";
        return;
      }
      // The selection changed while this decode was running.
      root.startPreviewIfIdle();
    }
  }

  Process {
    id: cleanupProcess

    command: [
      "sh",
      "-c",
      "find " + root.shellQuote(Quickshell.cacheDir)
        + " -maxdepth 1 -type f -name 'clipboard-*' -mtime +7 -delete 2>/dev/null"
    ]
  }

  Timer {
    id: focusTimer
    interval: 0
    repeat: false
    onTriggered: searchInput.forceActiveFocus()
  }

  Timer {
    id: previewTimer
    interval: 120
    repeat: false
    onTriggered: root.fetchPreview()
  }

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

    width: Math.min(900, root.width - 32)
    height: root.panelHeight
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.panelTop
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
      onClicked: searchInput.forceActiveFocus()
      onWheel: event => event.accepted = true
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 0

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 58

        RowLayout {
          anchors {
            fill: parent
            leftMargin: 16
            rightMargin: 16
          }
          spacing: 12

          Text {
            text: "\uf0ea"
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
                root.rebuild(true);
              }
              onAccepted: root.copySelected()

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
                case Qt.Key_Delete:
                  if (ctrl || shift) {
                    root.removeSelected();
                    event.accepted = true;
                  }
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
              text: "Search clipboard history…"
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
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.divider
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        Item {
          Layout.preferredWidth: Math.round(panel.width * 0.55)
          Layout.fillHeight: true

          ListView {
            id: resultList

            anchors.fill: parent
            topMargin: 4
            bottomMargin: 4
            model: root.results
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: root.results.length > root.maxVisibleRows
            visible: root.results.length > 0

            delegate: Item {
              id: row

              required property var modelData
              required property int index

              width: ListView.view.width
              height: root.rowHeight

              readonly property bool selected: index === root.selectedIndex
              readonly property bool hasThumb: root.thumbSource(row.modelData.id) !== ""

              Component.onCompleted: root.requestThumb(row.modelData)

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
                  : (mouse.containsMouse ? Theme.rowHover : Theme.clear(Theme.rowHover))

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
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                onClicked: event => {
                  if (event.button === Qt.MiddleButton) {
                    root.removeAt(row.index);
                    return;
                  }
                  root.selectedIndex = row.index;
                  root.copyEntry(row.modelData);
                }
              }

              RowLayout {
                anchors {
                  fill: parent
                  leftMargin: 14
                  rightMargin: 14
                  topMargin: 6
                  bottomMargin: 6
                }
                spacing: 12

                Item {
                  Layout.preferredWidth: 40
                  Layout.preferredHeight: 40

                  Rectangle {
                    anchors.fill: parent
                    visible: !row.modelData.image
                    radius: 8
                    color: row.selected
                      ? Qt.rgba(1, 1, 1, 0.18)
                      : Theme.surface

                    Text {
                      anchors.centerIn: parent
                      text: "\uf0ea"
                      color: row.selected ? Theme.accentText : Theme.accent
                      font.family: Theme.fontFamily
                      font.pixelSize: 18
                      textFormat: Text.PlainText
                    }
                  }

                  ClippingRectangle {
                    anchors.fill: parent
                    visible: row.modelData.image
                    radius: 8
                    color: Theme.surface

                    Text {
                      anchors.centerIn: parent
                      visible: !row.hasThumb
                      text: "\uf03e"
                      color: row.selected ? Theme.accentText : Theme.textMuted
                      font.family: Theme.fontFamily
                      font.pixelSize: 16
                      textFormat: Text.PlainText
                    }

                    Image {
                      anchors.fill: parent
                      visible: row.hasThumb
                      source: root.thumbSource(row.modelData.id)
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: false
                      sourceSize.width: 80
                      sourceSize.height: 80

                      onStatusChanged: {
                        if (status === Image.Error)
                          root.cacheThumb(row.modelData.id, "", true);
                      }
                    }
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    Layout.fillWidth: true
                    text: root.rowTitle(row.modelData)
                    color: row.selected ? Theme.accentText : Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                  }

                  Text {
                    Layout.fillWidth: true
                    text: root.rowSubtitle(row.modelData)
                    color: row.selected ? Theme.accentText : Theme.textSecondary
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
            width: parent.width - 32
            visible: root.results.length === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.emptyMessage
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 12
            textFormat: Text.PlainText
          }
        }

        Rectangle {
          Layout.preferredWidth: 1
          Layout.fillHeight: true
          color: Theme.divider
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            RowLayout {
              anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 16
              }
              spacing: 8

              Text {
                text: "Preview"
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
                textFormat: Text.PlainText
              }

              Item {
                Layout.fillWidth: true
              }

              Text {
                text: root.selectedBadge
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 10
                textFormat: Text.PlainText
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.divider
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
              anchors.fill: parent
              anchors.margins: 16
              visible: root.selectedEntry !== null
                && !root.selectedEntry.image
                && root.selectedPreviewLoaded
              contentWidth: width
              contentHeight: previewBody.height
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: previewBody

                width: parent.width
                text: root.selectedPreviewText
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                textFormat: Text.PlainText
              }
            }

            Image {
              anchors.fill: parent
              anchors.margins: 16
              visible: root.selectedEntry !== null
                && root.selectedEntry.image
                && root.selectedHasThumb
              source: root.selectedHasThumb ? root.selectedThumb.source : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: false
              sourceSize.width: 560
              sourceSize.height: 420

              onStatusChanged: {
                if (status !== Image.Error || root.selectedEntry === null)
                  return;
                if (source === root.thumbSource(root.selectedEntry.id))
                  root.cacheThumb(root.selectedEntry.id, "", true);
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width - 32
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              color: Theme.textMuted
              font.family: Theme.fontFamily
              font.pixelSize: 11
              textFormat: Text.PlainText
              text: {
                const entry = root.selectedEntry;
                if (!entry)
                  return root.results.length === 0 ? "" : "Select an entry to preview";
                if (entry.image) {
                  if (root.selectedHasThumb)
                    return "";
                  return root.hasThumbFailed(entry.id) ? "Preview unavailable" : "Loading image…";
                }
                if (entry.binary)
                  return "Binary data";
                if (!root.selectedPreviewLoaded) {
                  if (root.previewError !== "")
                    return root.previewError;
                  return "Loading preview…";
                }
                if (root.selectedPreviewText === "")
                  return "(empty clip)";
                return "";
              }
              visible: text !== ""
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.divider
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 34

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
            text: "↑↓ navigate · Enter copy · Ctrl+Del delete · Esc close"
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
