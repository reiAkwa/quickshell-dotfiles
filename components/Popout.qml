pragma Singleton

import Quickshell

// Tracks which bar popout is open. Keys include the screen name so each
// monitor can keep its own popout without opening panels everywhere.
Singleton {
  id: root

  property string current: ""
  property string trigger: ""

  function toggle(key) {
    root.current = root.current === key ? "" : key;
    root.trigger = "";
  }

  // Two bar modules can share one popout (CPU and memory both open the task
  // manager). Clicking the other trigger keeps the shared panel open and only
  // moves it; clicking the same trigger again closes it like a normal toggle.
  function toggleAt(key, triggerName) {
    if (root.current === key && root.trigger === triggerName) {
      root.current = "";
      root.trigger = "";
    } else {
      root.current = key;
      root.trigger = triggerName;
    }
  }

  function close(key) {
    if (root.current === key) {
      root.current = "";
      root.trigger = "";
    }
  }

  // Close only the popout owned by one screen. Keys are "<screen>:<domain>",
  // so a click on another monitor's bar must not dismiss this one.
  function dismissFor(screen) {
    if (screen !== "" && root.current.startsWith(screen + ":")) {
      root.current = "";
      root.trigger = "";
    }
  }
}
