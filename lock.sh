#!/bin/sh
# Lock the niri session with the Quickshell lock screen.
#
# Used by the Super+Alt+L bind, by swayidle, and by relock.sh. If the shell is
# not running (or an older shell without the `lock` IPC target is running),
# fall back to swaylock so the session still gets locked.
set -u

# A crash-restarted qs.service can still be starting while swayidle resumes.
# Give an activating shell a short window to answer IPC before falling back to
# swaylock, otherwise the resume path would show the wrong lock screen.
if command -v systemctl >/dev/null 2>&1; then
  i=0
  while [ "$i" -lt 30 ]; do
    qs -c niri ipc call lock isLocked >/dev/null 2>&1 && break
    state=$(systemctl --user show qs.service -p ActiveState --value 2>/dev/null) || state=""
    case "$state" in
      activating|reloading) ;;
      *) break ;;
    esac
    sleep 0.1
    i=$((i + 1))
  done
fi

# Start swaylock in the background and wait for its readiness notification.
# `-f` keeps swayidle's before-sleep hook from blocking until unlock; the ready
# fd (3) tells us when the lock is actually up, so suspend cannot race it.
fallback() {
  command -v swaylock >/dev/null 2>&1 || {
    echo "lock.sh: quickshell is unavailable and swaylock is not installed" >&2
    return 0
  }

  ready=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/swaylock-ready.XXXXXX") || {
    swaylock -f
    return 0
  }
  swaylock -f -R 3 3>"$ready"
  i=0
  while [ "$i" -lt 60 ] && [ ! -s "$ready" ]; do
    sleep 0.05
    i=$((i + 1))
  done
  rm -f "$ready"
  return 0
}

out=$(qs -c niri ipc call lock lock 2>&1) || { fallback; exit 0; }
case "$out" in
  ""|true) ;;
  *) fallback; exit 0 ;;
esac

# Wait until the compositor confirms that every output is covered. This matters
# for swayidle's before-sleep hook: suspending before the lock is mapped can
# expose the desktop for a moment after resume.
i=0
while [ "$i" -lt 60 ]; do
  [ "$(qs -c niri ipc call lock isSecure 2>/dev/null)" = "true" ] && exit 0
  sleep 0.05
  i=$((i + 1))
done

# Quickshell is running but did not manage to lock (for example niri refused
# its lock request after the previous client died). Try the independent
# fallback rather than leaving the session unlocked.
fallback
exit 0
