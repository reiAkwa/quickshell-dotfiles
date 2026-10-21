pragma Singleton

import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

// Data engine for the task manager popout. Everything is sampled from /proc
// with Quickshell's own Process type; no htop/top/ps process is spawned.
//
// A sample contains three sections:
//   @@STAT@@  /proc/stat          overall CPU jiffies + core count
//   @@MEM@@   /proc/meminfo       memory and swap totals
//   @@PROC@@  /proc/<pid>/stat    per-process CPU time and RSS
//
// Process CPU percentages are deltas between two samples, so the first sample
// only establishes a baseline. Opening the panel schedules a quick second
// sample so the list is populated immediately instead of after two seconds.
Singleton {
  id: root

  property bool panelOpen: false
  property real anchorRight: 0

  property int cpuUsage: 0
  property int cpuCount: 1
  property real memoryUsedBytes: 0
  property real memoryTotalBytes: 0
  property real swapUsedBytes: 0
  property real swapTotalBytes: 0

  readonly property int memoryPercentage: memoryTotalBytes > 0
    ? Math.round(memoryUsedBytes * 100 / memoryTotalBytes)
    : 0
  readonly property int swapPercentage: swapTotalBytes > 0
    ? Math.round(swapUsedBytes * 100 / swapTotalBytes)
    : 0

  // Raw sorted process rows. The ListView binds to processModel below, which
  // is updated in place so live refreshes do not reset the scroll position.
  property var processes: []
  property string sortKey: "cpu"
  property int processCount: 0

  property double lastTotalJiffies: 0
  property double lastIdleJiffies: 0
  property var lastProcessJiffies: ({})
  property bool hasProcessBaseline: false
  property int pageSize: 4096

  ListModel {
    id: processModelData
  }

  property ListModel processModel: processModelData

  readonly property string snapshotScript: "echo @@STAT@@; cat /proc/stat; echo @@MEM@@; cat /proc/meminfo; echo @@PROC@@; for f in /proc/[0-9]*/stat; do read -r line < \"$f\" || continue; pid=${f#/proc/}; pid=${pid%/stat}; comm=${line#*(}; comm=${comm%%)*}; rest=${line##*) }; set -- $rest; printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$pid\" \"${12}\" \"${13}\" \"${22}\" \"$comm\"; done"

  function setPanelOpen(open) {
    if (root.panelOpen === open)
      return;

    root.panelOpen = open;
    if (open) {
      // Discard the old baseline: CPU percentages should describe the
      // current panel session, not the time since it was last open.
      root.lastTotalJiffies = 0;
      root.lastIdleJiffies = 0;
      root.lastProcessJiffies = ({});
      root.hasProcessBaseline = false;
      root.sampleNow();
    }
  }

  function sampleNow() {
    if (snapshotProcess.running)
      return;
    snapshotProcess.running = true;
  }

  function clampPercent(value) {
    return Math.max(0, Math.min(100, value));
  }

  function sortRows(rows) {
    const list = rows.slice();
    if (root.sortKey === "memory") {
      list.sort((a, b) => (b.rssBytes - a.rssBytes) || (b.cpu - a.cpu));
    } else if (root.sortKey === "name") {
      list.sort((a, b) => a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
    } else {
      list.sort((a, b) => (b.cpu - a.cpu) || (b.rssBytes - a.rssBytes));
    }
    return list;
  }

  function publishProcesses(rows) {
    root.processes = rows;
    root.processCount = rows.length;
    root.syncProcessModel(root.sortRows(rows));
  }

  onSortKeyChanged: {
    root.syncProcessModel(root.sortRows(root.processes));
  }

  // Update ListModel entries in place. Replacing the whole model on every
  // 2-second sample would reset the ListView scroll position.
  function syncProcessModel(rows) {
    while (processModelData.count > rows.length)
      processModelData.remove(processModelData.count - 1);

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      if (i >= processModelData.count) {
        processModelData.append({
          pid: row.pid,
          name: row.name,
          cpu: row.cpu,
          rssBytes: row.rssBytes
        });
        continue;
      }

      const current = processModelData.get(i);
      if (current.pid !== row.pid)
        processModelData.setProperty(i, "pid", row.pid);
      if (current.name !== row.name)
        processModelData.setProperty(i, "name", row.name);
      if (current.cpu !== row.cpu)
        processModelData.setProperty(i, "cpu", row.cpu);
      if (current.rssBytes !== row.rssBytes)
        processModelData.setProperty(i, "rssBytes", row.rssBytes);
    }
  }

  function parseSnapshot(text) {
    const lines = text.split("\n");
    let section = "";
    let cpuFields = null;
    let cores = 0;
    let memTotal = 0;
    let memAvailable = 0;
    let swapTotal = 0;
    let swapFree = 0;
    const rawProcesses = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line === "@@STAT@@") {
        section = "stat";
        continue;
      }
      if (line === "@@MEM@@") {
        section = "mem";
        continue;
      }
      if (line === "@@PROC@@") {
        section = "proc";
        continue;
      }
      if (line === "")
        continue;

      if (section === "stat") {
        if (line.startsWith("cpu ")) {
          cpuFields = line.trim().split(/\s+/).slice(1).map(Number);
        } else if (line.startsWith("cpu")) {
          cores++;
        }
      } else if (section === "mem") {
        const match = line.match(/^(\w+):\s+(\d+)/);
        if (!match)
          continue;
        const bytes = Number(match[2]) * 1024;
        if (match[1] === "MemTotal")
          memTotal = bytes;
        else if (match[1] === "MemAvailable")
          memAvailable = bytes;
        else if (match[1] === "SwapTotal")
          swapTotal = bytes;
        else if (match[1] === "SwapFree")
          swapFree = bytes;
      } else if (section === "proc") {
        const parts = line.split("\t", 5);
        if (parts.length < 5)
          continue;

        const pid = Number(parts[0]);
        const jiffies = Number(parts[1]) + Number(parts[2]);
        const rssPages = Number(parts[3]);
        const name = parts[4] || "?";
        if (!pid || !isFinite(jiffies))
          continue;

        rawProcesses.push({
          pid: pid,
          name: name,
          jiffies: jiffies,
          rssPages: rssPages
        });
      }
    }

    let totalDelta = 0;
    let idleDelta = 0;
    if (cpuFields && cpuFields.length >= 4) {
      let total = 0;
      for (let i = 0; i < Math.min(8, cpuFields.length); i++)
        total += cpuFields[i] || 0;
      const idle = (cpuFields[3] || 0) + (cpuFields[4] || 0);

      if (root.lastTotalJiffies > 0 && total > root.lastTotalJiffies) {
        totalDelta = total - root.lastTotalJiffies;
        idleDelta = Math.max(0, idle - root.lastIdleJiffies);
        root.cpuUsage = Math.round(root.clampPercent(
          (1 - idleDelta / totalDelta) * 100));
      }

      root.lastTotalJiffies = total;
      root.lastIdleJiffies = idle;
    }

    root.cpuCount = Math.max(1, cores);
    root.memoryTotalBytes = memTotal;
    root.memoryUsedBytes = Math.max(0, memTotal - memAvailable);
    root.swapTotalBytes = swapTotal;
    root.swapUsedBytes = Math.max(0, swapTotal - swapFree);

    const nextJiffies = ({});
    const rows = [];
    const cpuScale = totalDelta > 0
      ? root.cpuCount / totalDelta * 100
      : 0;

    for (let i = 0; i < rawProcesses.length; i++) {
      const raw = rawProcesses[i];
      nextJiffies[raw.pid] = raw.jiffies;

      let cpu = 0;
      const previous = root.lastProcessJiffies[raw.pid];
      if (previous !== undefined && cpuScale > 0)
        cpu = Math.max(0, raw.jiffies - previous) * cpuScale;

      rows.push({
        pid: raw.pid,
        name: raw.name,
        cpu: cpu,
        rssBytes: Math.max(0, raw.rssPages || 0) * root.pageSize
      });
    }

    root.lastProcessJiffies = nextJiffies;
    root.publishProcesses(rows);

    // The first sample has no previous jiffies. Take a second one shortly
    // after it so process percentages appear without waiting for the full
    // two-second refresh interval.
    if (!root.hasProcessBaseline) {
      root.hasProcessBaseline = true;
      primeTimer.restart();
    }
  }

  function terminate(pid) {
    if (pid <= 1)
      return;
    killProcess.command = ["kill", "-TERM", String(pid)];
    killProcess.running = true;
  }

  function formatBytes(bytes) {
    if (bytes >= 1024 * 1024 * 1024)
      return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GiB";
    if (bytes >= 1024 * 1024)
      return Math.round(bytes / (1024 * 1024)) + " MiB";
    if (bytes >= 1024)
      return Math.round(bytes / 1024) + " KiB";
    return Math.round(bytes) + " B";
  }

  function formatCompact(bytes) {
    if (bytes >= 1024 * 1024 * 1024)
      return (bytes / (1024 * 1024 * 1024)).toFixed(1) + "G";
    if (bytes >= 1024 * 1024)
      return Math.round(bytes / (1024 * 1024)) + "M";
    if (bytes >= 1024)
      return Math.round(bytes / 1024) + "K";
    return Math.round(bytes) + "B";
  }

  function formatCpu(value) {
    if (value >= 10)
      return Math.round(value) + "%";
    return value.toFixed(1) + "%";
  }

  Timer {
    interval: 2000
    running: root.panelOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleNow()
  }

  Timer {
    id: primeTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (root.panelOpen)
        root.sampleNow();
    }
  }

  Process {
    id: snapshotProcess
    command: ["sh", "-c", root.snapshotScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSnapshot(text)
    }
  }

  Process {
    id: pageSizeProcess
    command: ["getconf", "PAGESIZE"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const value = Number(text.trim());
        if (value > 0)
          root.pageSize = value;
      }
    }
  }

  Process {
    id: killProcess
    command: ["true"]
    running: false
  }

  Component.onCompleted: pageSizeProcess.running = true
}
