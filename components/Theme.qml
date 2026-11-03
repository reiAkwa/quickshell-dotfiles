pragma Singleton

import Quickshell
import QtQuick

// Palette and measurements copied from ~/.config/waybar/style.css.
Singleton {
  id: root

  // Bar
  readonly property color background: "#f0f8ff"
  readonly property color foreground: "#3b3b3b"
  readonly property color accent: "#56a0d1"
  readonly property int barHeight: 44
  readonly property int borderWidth: 3

  // Modules
  readonly property color window: "#dae2e9"
  readonly property color clock: "#dae2e9"
  readonly property color audio: "#cfb886"
  readonly property color network: "#5b7f92"
  readonly property color bluetooth: "#7897c7"
  readonly property color cpu: "#56a0d1"
  readonly property color memory: "#7fad9c"
  readonly property color battery: "#cba0e3"
  readonly property color tray: "#a8b4c0"
  readonly property color notification: "#b6aec9"
  readonly property color notificationActive: "#e0a458"
  readonly property color awayActive: "#ffd54f"
  readonly property color dndOn: "#d97b7b"
  readonly property color dndOnForeground: "#f0f8ff"

  // Shared control surfaces and text roles used by the popouts and toast
  // cards. Kept separate from the per-module palette above so a popout can
  // adopt one role without inheriting a module color.
  readonly property color textStrong: "#5b6773"
  readonly property color textSecondary: "#6d7c8a"
  readonly property color textMuted: "#9aa7b3"
  readonly property color textDisabled: "#7b8794"
  readonly property color divider: "#c9d6e2"
  readonly property color surface: "#dce7f0"
  readonly property color surfaceHover: "#cfdeea"
  readonly property color rowHover: "#e4eef7"
  readonly property color inactive: "#c8d2dc"
  readonly property color accentText: "#ffffff"
  readonly property color danger: "#b44"
  readonly property color alert: "#d9534f"

  readonly property int moduleHeight: 41
  readonly property int moduleRadius: 10
  readonly property int modulePadding: 10

  // A fully transparent copy of `color`, keeping its hue. A ColorAnimation
  // between a real colour and the literal "transparent" interpolates through
  // transparent *black*, so a hover highlight flashes dark grey before it
  // settles on the tint. Fading between a colour and its own zero-alpha copy
  // only moves the alpha channel.
  function clear(color) {
    return Qt.rgba(color.r, color.g, color.b, 0);
  }

  // GTK resolves the CSS to 11pt in the original bar. At 96 DPI that is
  // 14.666px; 14px produces the same 7px Iosevka advance width.
  readonly property int fontSize: 14
  readonly property string fontFamily: "IosevkaTerm Nerd Font"

  // Motion. Animations never use the default linear curve: color changes get
  // a short decelerating fade, movement gets a fast-then-settle quintic curve,
  // and exits leave faster than they arrived. Keeping durations here makes
  // every surface (bar, popouts, overlays) feel like one system.
  readonly property int motionFast: 120
  readonly property int motionBase: 190
  readonly property int motionSlow: 260
  readonly property int motionExit: 140

  readonly property int easeStandard: Easing.OutCubic
  readonly property int easeEnter: Easing.OutQuint
  readonly property int easeExit: Easing.InCubic

  // Waybar's window module: max-length 50, ellipsized at 367px.
  readonly property int windowTextMaxWidth: 367

  // Workspaces use icon chips instead of plain numbers.
  readonly property color workspaceInactive: "#dae2e9"
  readonly property int workspaceButtonWidth: 41

  // Tray defaults
  readonly property int trayIconSize: 16
}

