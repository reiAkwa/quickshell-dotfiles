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

  function dismiss() {
    root.current = "";
  }
}
