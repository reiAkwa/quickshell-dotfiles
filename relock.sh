#!/bin/sh
# Re-request the Quickshell lock after the shell (re)starts.
#
# Run as ExecStartPost= for qs.service. If niri still reports the logind
# session as locked, the previous shell died while the screen was locked and
# niri is showing its red "locked session" background. Asking the fresh shell
# to lock replaces the dead lock, so the real lock screen comes back instead of
# staying red.
set -u

session="${XDG_SESSION_ID:-}"
[ -n "$session" ] || exit 0
[ "$(loginctl show-session "$session" -p LockedHint --value 2>/dev/null)" = "yes" ] || exit 0

# Wait for the new shell's IPC to answer (max ~5s) so we do not race its start
# and fall back to swaylock needlessly.
i=0
while [ "$i" -lt 50 ]; do
  qs -c niri ipc call lock isLocked >/dev/null 2>&1 && break
  sleep 0.1
  i=$((i + 1))
done

exec "$(dirname "$0")/lock.sh"
