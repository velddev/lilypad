import QtQuick

// Drives a popover's opacity. Opening jumps straight to 40% and fades up from
// there, so the popover is on screen in the very first frame after the click (a fade
// from nothing spends its first frames invisible). Closing fades out to nothing, or
// with fadeOut false hides at once (for popovers whose visibility follows `opened`).
// Closing one that is still fading in hides it at once too: a reversal is instant.
Item {
  id: fade
  required property Item target
  property bool opened: false
  property real from: 0.4
  property int openDuration: PanelStyle.openDuration
  property int closeDuration: 140
  property int closeEasing: Easing.InOutQuad
  property bool fadeOut: true
  onOpenedChanged: {
    if (opened) {
      fadeDown.stop();
      target.opacity = from;
      fadeUp.restart();
    } else {
      const interrupted = fadeUp.running;
      fadeUp.stop();
      if (fadeOut && !interrupted) fadeDown.restart();
      else target.opacity = 0;
    }
  }
  NumberAnimation {
    id: fadeUp
    target: fade.target; property: "opacity"; to: 1
    duration: fade.openDuration; easing.type: Easing.OutCubic
  }
  NumberAnimation {
    id: fadeDown
    target: fade.target; property: "opacity"; to: 0
    duration: fade.closeDuration; easing.type: fade.closeEasing
  }
}
