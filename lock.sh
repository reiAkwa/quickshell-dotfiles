#!/bin/sh
# Lock the niri session with the Quickshell lock screen.
#
# Used by the Super+Alt+L bind and by swayidle. If the shell is not running (or
# an older shell without the `lock` IPC target is running), fall back to
# swaylock so the session still gets locked.
set -u

out=$(qs -c niri ipc call lock lock 2>&1) || { exec swaylock -f; }
case "$out" in
  ""|true) ;;
  *) exec swaylock -f ;;
esac

# Wait until the compositor confirms that every output is covered. This matters
# for swayidle's before-sleep hook: suspending before the lock is mapped can
# expose the desktop for a moment after resume.
i=0
while [ "$i" -lt 40 ]; do
  [ "$(qs -c niri ipc call lock isSecure 2>/dev/null)" = "true" ] && exit 0
  sleep 0.05
  i=$((i + 1))
done

exit 0
