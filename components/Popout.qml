pragma Singleton

import Quickshell

// Tracks which bar popout is open. Keys include the screen name so each
// monitor can keep its own popout without opening panels everywhere.
Singleton {
  id: root

  property string current: ""

  function toggle(key) {
    root.current = root.current === key ? "" : key;
  }

  function close(key) {
    if (root.current === key)
      root.current = "";
  }

  // Close only the popout owned by one screen. Keys are "<screen>:<domain>",
  // so a click on another monitor's bar must not dismiss this one.
  function dismissFor(screen) {
    if (screen !== "" && root.current.startsWith(screen + ":"))
      root.current = "";
  }
}
