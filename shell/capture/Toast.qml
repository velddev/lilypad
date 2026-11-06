pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "." as Capture
import ".." as Shell

// iPhone-style capture thumbnail: slides into the bottom-right corner,
// click to open, Ctrl+click to show it in its folder, swipe right to put it away.
// The file is already saved; dismissing never deletes it.
PanelWindow {
  id: root

  required property string outputName
  readonly property bool mine: Capture.State.path !== ""
      && (Capture.State.outputName === "" || Capture.State.outputName === outputName)
  readonly property int edge: 16
  readonly property int cardWidth: 240
  readonly property real aspect: thumbnail.implicitWidth > 0
      ? thumbnail.implicitHeight / thumbnail.implicitWidth : 0.6
  readonly property int cardHeight: Math.round(Math.max(110, Math.min(300, cardWidth * aspect)))
  property bool leaving: false
  // Horizontal offset of the card: 0 is resting, cardWidth + edge is off-screen.
  property real offset: cardWidth + edge

  color: "transparent"
  visible: mine || offset < cardWidth + edge - 0.5
  anchors { right: true; bottom: true }
  margins.bottom: edge
  implicitWidth: cardWidth + edge
  implicitHeight: cardHeight + 12
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "lilypad-toast"
  // A client only sees modifiers while it has the keyboard, so a click brings it here for Ctrl.
  // Only under the pointer: niri focuses a new on-demand surface, and that would stop your typing.
  WlrLayershell.keyboardFocus: hover.hovered ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  function slideIn() {
    leaving = false;
    exit.stop();
    offset = cardWidth + edge;
    enter.restart();
    dismissTimer.restart();
  }

  function slideOut() {
    if (leaving) return;
    leaving = true;
    enter.stop();
    exit.from = offset;
    exit.restart();
  }

  Connections {
    target: Capture.State
    function onGenerationChanged() { if (root.mine) root.slideIn(); }
    function onPathChanged() { if (Capture.State.path === "" && !root.leaving) root.slideOut(); }
  }

  NumberAnimation {
    id: enter
    target: root; property: "offset"; to: 0
    duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.6
  }
  NumberAnimation {
    id: exit
    target: root; property: "offset"; to: root.cardWidth + root.edge
    duration: 200; easing.type: Easing.InCubic
    onFinished: if (root.leaving && Capture.State.path !== "") Capture.State.dismiss()
  }
  NumberAnimation {
    id: snapBack
    target: root; property: "offset"; to: 0
    duration: 220; easing.type: Easing.OutCubic
  }

  Timer {
    id: dismissTimer
    interval: 8000
    running: false
    onTriggered: {
      if (hover.hovered || swipe.active || Capture.State.converting !== "") restart();
      else root.slideOut();
    }
  }

  Item {
    id: card
    x: root.offset
    y: 6
    width: root.cardWidth
    height: root.cardHeight
    opacity: 1 - Math.max(0, root.offset) / (root.cardWidth + root.edge) * 0.6

    Rectangle {
      id: shadowShape
      anchors.fill: parent
      radius: 14
      color: "black"
      visible: false
      layer.enabled: true
    }
    MultiEffect {
      anchors.fill: parent
      source: shadowShape
      shadowEnabled: true
      shadowColor: "black"
      shadowOpacity: 0.45
      shadowBlur: 0.8
      shadowVerticalOffset: 3
      blurMax: 24
    }

    ClippingRectangle {
      anchors.fill: parent
      radius: 14
      color: "#2a2a2a"
      border { width: 1; color: "#30ffffff" }

      Image {
        id: thumbnail
        anchors.fill: parent
        source: Capture.State.thumb ? "file://" + Capture.State.thumb + "?r=" + Capture.State.revision : ""
        sourceSize.width: root.cardWidth * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
      }

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: hover.hovered ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      // Video badge
      Rectangle {
        visible: Capture.State.isVideo
        anchors { left: parent.left; top: parent.top; margins: 8 }
        width: badge.implicitWidth + 14
        height: 20
        radius: 10
        color: "#b0000000"
        Text {
          id: badge
          anchors.centerIn: parent
          text: "▶  " + Capture.State.extension.toUpperCase()
          color: "white"
          font { family: Shell.PanelStyle.fontFamily; pixelSize: 11; weight: Font.DemiBold }
        }
      }

      // Status line: conversions and short confirmations
      Rectangle {
        readonly property string text: Capture.State.converting !== ""
            ? "Converting to " + Capture.State.converting.toUpperCase() + "…" : Capture.State.notice
        visible: text !== ""
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
        width: status.implicitWidth + 20
        height: 24
        radius: 12
        color: "#CBA6F7"
        Text {
          id: status
          anchors.centerIn: parent
          text: parent.text
          color: "#3D2C52"
          font { family: Shell.PanelStyle.fontFamily; pixelSize: 12; weight: Font.Medium }
        }
      }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    TapHandler {
      gesturePolicy: TapHandler.DragThreshold
      onTapped: Capture.State.act(point.modifiers & Qt.ControlModifier ? "reveal" : "open")
    }

    // Swipe right to dismiss; dragging left only gives a little resistance.
    DragHandler {
      id: swipe
      target: null
      yAxis.enabled: false
      property real startOffset: 0
      onActiveChanged: {
        if (active) {
          enter.stop();
          snapBack.stop();
          startOffset = root.offset;
        } else if (root.offset > 60 || centroid.velocity.x > 600) {
          root.slideOut();
        } else {
          snapBack.restart();
          dismissTimer.restart();
        }
      }
      onTranslationChanged: {
        if (!active) return;
        const dx = translation.x;
        root.offset = startOffset + (dx > 0 ? dx : dx * 0.2);
      }
    }
  }
}
