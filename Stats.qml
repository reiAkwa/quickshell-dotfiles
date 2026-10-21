pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Minimal /proc readers for the two Waybar modules that use them. Waybar's
// default intervals are kept: 10s for CPU and 30s for memory.
Singleton {
  id: root

  property int cpuUsage: 0
  property int memoryPercentage: 0

  property real lastCpuTotal: 0
  property real lastCpuIdle: 0

  function updateCpu(text) {
    const line = text.split("\n")[0];
    const fields = line.trim().split(/\s+/).slice(1).map(Number);
    if (fields.length < 4)
      return;

    let total = 0;
    for (let i = 0; i < fields.length; i++)
      total += fields[i];

    const idle = fields[3] + (fields[4] || 0);
    if (root.lastCpuTotal > 0 && total > root.lastCpuTotal) {
      const used = (total - root.lastCpuTotal) - (idle - root.lastCpuIdle);
      root.cpuUsage = Math.max(0, Math.min(100,
        Math.round(used * 100 / (total - root.lastCpuTotal))));
    }

    root.lastCpuTotal = total;
    root.lastCpuIdle = idle;
  }

  function updateMemory(text) {
    let total = 0;
    let available = 0;

    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const match = lines[i].match(/^(\w+):\s+(\d+)/);
      if (!match)
        continue;
      if (match[1] === "MemTotal")
        total = Number(match[2]);
      else if (match[1] === "MemAvailable")
        available = Number(match[2]);
    }

    if (total > 0)
      root.memoryPercentage = Math.round((total - available) * 100 / total);
  }

  Process {
    id: cpuProcess
    command: ["cat", "/proc/stat"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateCpu(text)
    }
  }

  Process {
    id: memoryProcess
    command: ["cat", "/proc/meminfo"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateMemory(text)
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: cpuProcess.running = true
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: memoryProcess.running = true
  }
}
