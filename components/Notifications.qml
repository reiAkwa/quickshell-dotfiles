pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Owns the session's notification server (org.freedesktop.Notifications).
// Two views consume it: NotificationPopup draws transient toasts, and
// modules/NotificationCenter.qml lists the tracked history.
Singleton {
  id: root

  // Do Not Disturb. Critical notifications still get a toast.
  property bool dnd: false

  // Notifications currently shown as toasts, newest first. Capped at three so
  // a burst from one application cannot cover the whole screen.
  property var live: []

  // A toast arriving while the notification center is open is already visible
  // there, so it must not raise the unread counter.
  property bool centerOpen: false
  property int unseen: 0

  // Arrival timestamps keyed by notification id, used for relative labels.
  property var receivedAt: ({})

  // trackedNotifications is in arrival order; the center shows newest first.
  readonly property var history: server.trackedNotifications.values.slice().reverse()

  NotificationServer {
    id: server
    keepOnReload: true
    bodySupported: true
    bodyMarkupSupported: false
    bodyHyperlinksSupported: false
    bodyImagesSupported: false
    actionsSupported: true
    actionIconsSupported: false
    imageSupported: true
    persistenceSupported: true
    inlineReplySupported: false

    onNotification: notification => root.handle(notification)
  }

  onDndChanged: {
    if (!root.dnd)
      return;

    // Drop queued toasts but keep critical ones, which bypass Do Not Disturb.
    root.live = root.live.filter(
      n => n.urgency === NotificationUrgency.Critical
    );
  }

  function handle(notification) {
    // After a config reload the server re-emits existing tracked
    // notifications. They are already in the history list.
    if (notification.lastGeneration)
      return;

    // tracked stays true until the user removes the entry, so the history
    // outlives the toast. Notifications the client withdraws untrack
    // themselves and disappear from the history automatically.
    notification.tracked = true;
    root.receivedAt[notification.id] = Date.now();
    root.receivedAtChanged();
    if (!root.centerOpen)
      root.unseen += 1;
    root.trimHistory();

    notification.closed.connect(() => root.closeToast(notification));

    if (root.dnd && notification.urgency !== NotificationUrgency.Critical) {
      // Transient notifications should not linger in the history when they
      // never got a toast.
      if (notification.transient)
        notification.tracked = false;
      return;
    }

    root.live = [notification].concat(root.live).slice(0, 3);
  }

  function trimHistory() {
    const values = server.trackedNotifications.values;
    for (let i = 0; i < values.length - 100; i++)
      values[i].dismiss();
  }

  // Remove a notification from the toast stack. History keeps it unless the
  // client marked it transient, in which case it should not persist at all.
  function closeToast(notification) {
    root.live = root.live.filter(n => n !== notification);
    if (notification.transient && notification.tracked)
      notification.tracked = false;
  }

  function markSeen() {
    root.unseen = 0;
  }

  // Close every notification, including the history. Same as the old
  // `makoctl dismiss --all` bound to the DND module's right click.
  function clearAll() {
    root.live = [];
    const values = server.trackedNotifications.values.slice();
    for (let i = 0; i < values.length; i++)
      values[i].dismiss();
  }

  function invokeDefault(notification) {
    const actions = notification.actions;
    for (let i = 0; i < actions.length; i++) {
      if (actions[i].identifier === "default") {
        actions[i].invoke();
        return true;
      }
    }
    return false;
  }

  // -1 means "use the server default", 0 means "never expire".
  function timeoutMs(notification) {
    if (!notification)
      return 0;
    if (notification.urgency === NotificationUrgency.Critical)
      return 0;
    if (notification.expireTimeout === 0)
      return 0;
    if (notification.expireTimeout > 0)
      return Math.min(notification.expireTimeout * 1000, 10000);
    return 6000;
  }

  // appIcon is the common case; some clients only send image-path (which is
  // frequently just the application icon).
  function displayIcon(notification) {
    if (!notification)
      return "";
    if (notification.appIcon !== "")
      return root.iconSource(notification.appIcon);
    if (notification.image !== "")
      return root.iconSource(notification.image);
    return "";
  }

  function iconSource(icon) {
    if (!icon)
      return "";
    if (icon.startsWith("image://") || icon.startsWith("file://"))
      return icon;
    if (icon.startsWith("/"))
      return "file://" + icon;
    return Quickshell.iconPath(icon, "image-missing");
  }

  function timeAgo(id, now) {
    const received = root.receivedAt[id];
    if (!received)
      return "";
    const seconds = Math.max(0, Math.floor((now - received) / 1000));
    if (seconds < 60)
      return "now";
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60)
      return minutes + "m";
    const hours = Math.floor(minutes / 60);
    if (hours < 24)
      return hours + "h";
    return Math.floor(hours / 24) + "d";
  }
}
