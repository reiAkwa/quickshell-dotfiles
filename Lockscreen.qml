pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "components"

// Password-only ext-session-lock-v1 lock screen.
//
// `lock.sh` (and the niri keybind) asks the running shell to lock through
// `qs -c niri ipc call lock lock`. The bar stays alive behind the lock surface,
// so unlocking just drops the lock instead of restarting the whole shell.
Scope {
  id: root

  // Override with QS_LOCK_WALLPAPER, or change the fallback below. The image is
  // cropped to fill every output, matching swaybg's `-m fill`.
  readonly property string wallpaper: String(
    Quickshell.env("QS_LOCK_WALLPAPER") || "/home/reiakwa/wallpapers/1-1.jpg"
  )

  property bool authenticating: false
  property string errorText: ""

  // Only kept while one PAM conversation is in flight, then cleared.
  property string submittedPassword: ""

  // Surfaces are separate windows, so each input has to clear itself.
  signal inputCleared()

  function lockNow(): void {
    if (sessionLock.locked)
      return;

    root.authenticating = false;
    root.submittedPassword = "";
    root.errorText = "";
    root.inputCleared();
    sessionLock.locked = true;
  }

  function submit(password: string): void {
    if (root.authenticating)
      return;

    if (password.length === 0) {
      root.errorText = "请输入密码";
      return;
    }

    root.submittedPassword = password;
    root.authenticating = true;
    root.errorText = "";
    root.inputCleared();

    if (!pam.start()) {
      root.authenticating = false;
      root.submittedPassword = "";
      root.errorText = "无法启动认证";
    }
  }

  WlSessionLock {
    id: sessionLock

    onLockStateChanged: {
      // A new lock always starts from a clean slate; unlocking clears the
      // retained password as well. The per-surface fields are empty when a new
      // lock creates them, so only the shared state needs resetting here.
      root.authenticating = false;
      root.submittedPassword = "";
      root.errorText = "";
    }

    WlSessionLockSurface {
      id: surface
      color: "#101418"

      Image {
        anchors.fill: parent
        source: root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
      }

      // Keep the wallpaper visible while making the centered control readable
      // on both bright and dark images.
      Rectangle {
        anchors.fill: parent
        color: "#4d000000"
      }

      // Any click outside the field restores keyboard focus, which is useful
      // after the compositor has moved focus away from the lock surface.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: input.forceActiveFocus()
      }

      Rectangle {
        id: inputBox

        anchors.centerIn: parent
        width: Math.min(360, parent.width - 80)
        height: 58
        radius: 14
        color: "#b31a222a"
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : "#66ffffff"
        opacity: 0
        scale: 0.94

        Behavior on opacity {
          NumberAnimation {
            duration: Theme.motionSlow
            easing.type: Theme.easeStandard
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: Theme.motionSlow
            easing.type: Theme.easeEnter
          }
        }

        // Start after the lock surface has been committed; animating at
        // Component.onCompleted would finish while the surface is still bare.
        Timer {
          interval: 32
          running: true
          onTriggered: {
            inputBox.opacity = 1;
            inputBox.scale = 1;
          }
        }

        Text {
          anchors.centerIn: parent
          visible: input.text.length === 0 && !root.authenticating
          text: "输入密码"
          color: "#80ffffff"
          font.family: Theme.fontFamily
          font.pixelSize: 18
        }

        Text {
          anchors.centerIn: parent
          visible: root.authenticating
          text: "验证中…"
          color: "#80ffffff"
          font.family: Theme.fontFamily
          font.pixelSize: 18
        }

        TextInput {
          id: input

          anchors.fill: parent
          anchors.leftMargin: 18
          anchors.rightMargin: 18
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          echoMode: TextInput.Password
          font.family: Theme.fontFamily
          font.pixelSize: 20
          color: Theme.background
          selectionColor: Theme.accent
          selectedTextColor: "#ffffff"
          readOnly: root.authenticating
          clip: true
          focus: true
          cursorVisible: input.text.length > 0

          onAccepted: root.submit(input.text)
          onTextChanged: {
            if (input.text.length > 0 && root.errorText.length > 0)
              root.errorText = "";
          }
        }
      }

      // A short hint is enough; the lock screen intentionally has no clock,
      // media controls, or other modules yet.
      Text {
        anchors {
          top: inputBox.bottom
          topMargin: 14
          horizontalCenter: parent.horizontalCenter
        }
        visible: root.errorText.length === 0 && !root.authenticating
        text: "按 Enter 解锁"
        color: "#a6ffffff"
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        id: errorPill

        anchors {
          top: inputBox.bottom
          topMargin: 12
          horizontalCenter: parent.horizontalCenter
        }
        width: errorLabel.implicitWidth + 28
        height: 32
        radius: 16
        color: "#99000000"
        opacity: root.errorText.length > 0 ? 1 : 0
        scale: root.errorText.length > 0 ? 1 : 0.94
        visible: opacity > 0

        Behavior on opacity {
          NumberAnimation {
            duration: root.errorText.length > 0 ? Theme.motionBase : Theme.motionExit
            easing.type: root.errorText.length > 0 ? Theme.easeStandard : Theme.easeExit
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: root.errorText.length > 0 ? Theme.motionBase : Theme.motionExit
            easing.type: root.errorText.length > 0 ? Theme.easeEnter : Theme.easeExit
          }
        }

        Text {
          id: errorLabel

          anchors.centerIn: parent
          text: root.errorText
          color: "#ffb4ab"
          font.family: Theme.fontFamily
          font.pixelSize: 13
        }
      }

      Connections {
        target: root

        function onInputCleared(): void {
          input.text = "";
          Qt.callLater(() => {
            if (input)
              input.forceActiveFocus();
          });
        }
      }

      // Re-assert focus whenever it is lost (cold lock, failed password,
      // resume from suspend). Only do this for the surface the compositor has
      // actually activated, so idle monitor surfaces cannot fight over focus.
      Timer {
        interval: 250
        repeat: true
        running: !input.activeFocus && input.Window.active
        onTriggered: input.forceActiveFocus()
      }

      Component.onCompleted: Qt.callLater(input.forceActiveFocus)
    }
  }

  PamContext {
    id: pam

    config: "quickshell"
    configDirectory: Quickshell.shellDir + "/pam"

    // pam_unix asks for one response; respond whenever PAM requests it. This
    // also covers stacks that ask more than once.
    onPamMessage: {
      if (pam.responseRequired)
        pam.respond(root.submittedPassword);
    }

    onCompleted: function(result) {
      root.authenticating = false;
      root.submittedPassword = "";

      if (result === PamResult.Success) {
        root.errorText = "";
        sessionLock.locked = false;
        return;
      }

      root.errorText = result === PamResult.MaxTries
        ? "尝试次数过多，请稍后再试"
        : "密码错误，请重试";
      root.inputCleared();
    }

    onError: function(error) {
      root.authenticating = false;
      root.submittedPassword = "";
      root.errorText = "认证出错：" + PamError.toString(error);
      root.inputCleared();
    }
  }

  IpcHandler {
    target: "lock"

    function lock(): void { root.lockNow() }
    function isLocked(): bool { return sessionLock.locked }
    function isSecure(): bool { return sessionLock.secure }
  }
}
