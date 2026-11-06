pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Capture
import ".." as Shell

// Drawing over the live screen while recording, from the moment the recording's
// region is picked (with whatever was drawn in the picker). gpu-screen-recorder
// records the composited monitor, so strokes land in the video as they are drawn.
//   drawing off  click-through: the input mask holds only the toolbar
//   drawing on   the recorded monitor takes the pointer; right-click turns it off
// The toolbar never goes in the video: it sits outside the recorded region (below,
// above, right or left of it), else on another monitor, else nowhere (use the keys).
// Keyboard: on demand while drawing is on (a click on the overlay takes it, so Shift
// snaps lines and arrows, Esc turns drawing off, Ctrl+Z undoes), exclusive while a
// label is being typed, never otherwise. Toggle drawing from the toolbar, the
// recording indicator or Ctrl+Shift+6; Ctrl+Shift+Alt+6 clears. Stopping the
// recording clears everything.
PanelWindow {
  id: root

  required property string outputName
  readonly property bool active: Capture.State.liveActive
  readonly property bool recorded: Capture.State.recordOutput === outputName
  readonly property bool drawing: active && recorded && Capture.State.liveTool !== ""
  readonly property var spot: Capture.State.liveToolbarSpot
  readonly property bool toolbarHere: active && spot !== null && spot.output === outputName
  readonly property int gap: 12
  readonly property int margin: 8
  readonly property int swatchRoom: 46

  visible: active && (recorded || toolbarHere || editor.ops.length > 0)
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-capture-draw"
  WlrLayershell.keyboardFocus: editor.typing ? WlrKeyboardFocus.Exclusive
      : drawing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  BackgroundEffect.blurRegion: Shell.Theme.daylight && toolbarHere ? toolbarBlur : null

  // Where the toolbar goes, worked out by the recorded monitor's overlay: next to
  // the region on this monitor if the bar and its colour strip fit outside it.
  readonly property var placement: {
    if (!active || !recorded) return null;
    const r = Capture.State.recordRect;
    const w = toolbar.barItem.width, h = toolbar.barItem.height;
    const clampX = x => Math.max(margin, Math.min(width - w - margin, x));
    const clampY = y => Math.max(margin, Math.min(height - h - margin, y));
    if (r.y + r.height + gap + h + swatchRoom + margin <= height)
      return { output: outputName, x: clampX(r.x + (r.width - w) / 2), y: r.y + r.height + gap, below: true };
    if (r.y - gap - h - swatchRoom >= margin)
      return { output: outputName, x: clampX(r.x + (r.width - w) / 2), y: r.y - gap - h, below: false };
    const y = clampY(r.y + (r.height - h) / 2);
    const below = y + h + swatchRoom + margin <= height;
    if (r.x + r.width + gap + w + margin <= width)
      return { output: outputName, x: r.x + r.width + gap, y: y, below: below };
    if (r.x - gap - w >= margin)
      return { output: outputName, x: r.x - gap - w, y: y, below: below };
    const other = Quickshell.screens.find(s => s.name !== outputName);
    return other ? { output: other.name, x: -1, y: -1, below: false } : null;
  }
  onPlacementChanged: if (recorded) Capture.State.liveToolbarSpot = placement

  // Quickshell sends a new input mask only with a rendered frame. Nudge one
  // invisible pixel whenever the mask changes so it never goes stale.
  property int maskStamp: 0
  onDrawingChanged: ++maskStamp
  onToolbarHereChanged: ++maskStamp
  Connections {
    target: toolbar
    function onSwatchesShownChanged() { ++root.maskStamp; }
  }
  Rectangle {
    width: 1
    height: 1
    color: root.maskStamp % 2 ? Qt.rgba(0, 0, 0, 0.004) : Qt.rgba(0, 0, 0, 0.008)
  }

  mask: Region {
    Region { width: root.drawing ? root.width : 0; height: root.drawing ? root.height : 0 }
    Region {
      x: toolbar.barItem.x; y: toolbar.barItem.y
      width: root.toolbarHere ? toolbar.barItem.width : 0
      height: root.toolbarHere ? toolbar.barItem.height : 0
    }
    Region {
      x: toolbar.swatchItem.x; y: toolbar.swatchItem.y
      width: root.toolbarHere && toolbar.swatchesShown ? toolbar.swatchItem.width : 0
      height: root.toolbarHere && toolbar.swatchesShown ? toolbar.swatchItem.height : 0
    }
  }

  Region {
    id: toolbarBlur
    Region {
      x: toolbar.barItem.x; y: toolbar.barItem.y
      width: toolbar.barItem.visible ? toolbar.barItem.width : 0
      height: toolbar.barItem.visible ? toolbar.barItem.height : 0
      radius: Shell.PanelStyle.radius
    }
    Region {
      x: toolbar.swatchItem.x; y: toolbar.swatchItem.y
      width: toolbar.swatchesShown ? toolbar.swatchItem.width : 0
      height: toolbar.swatchesShown ? toolbar.swatchItem.height : 0
      radius: Shell.PanelStyle.radius
    }
  }

  Connections {
    target: Capture.State
    function onLiveActiveChanged() {
      if (!Capture.State.liveActive) {
        editor.reset();
        return;
      }
      const carried = Capture.State.carried[root.outputName];
      if (carried) editor.load(carried);
    }
    function onClearLive() { editor.reset(); }
  }

  Capture.Editor {
    id: editor
    anchors.fill: parent
    outputName: root.outputName
    channel: "live"
    tool: Capture.State.liveTool
    color: Capture.State.liveColor
    fadeAfter: Capture.State.liveFade ? 3000 : 0
    onTypingChanged: if (typing) keys.forceActiveFocus()
  }

  Item {
    id: keys
    focus: true
    readonly property var toolKeys: ({
      [Qt.Key_P]: "pen", [Qt.Key_A]: "arrow", [Qt.Key_L]: "line", [Qt.Key_R]: "rect",
      [Qt.Key_T]: "text", [Qt.Key_H]: "marker"
    })
    Keys.onPressed: event => {
      const ctrl = event.modifiers & Qt.ControlModifier;
      if (editor.typing) {
        if (event.key === Qt.Key_Escape) editor.cancelText();
        else editor.typeKey(event.key, event.modifiers, event.text);
      } else if (event.key === Qt.Key_Escape) Capture.State.setLiveTool("");
      else if (ctrl && event.key === Qt.Key_Z) Capture.State.liveUndo();
      else if (!ctrl && toolKeys[event.key]) Capture.State.setLiveTool(toolKeys[event.key]);
      else return;
      event.accepted = true;
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.drawing
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Capture.State.liveTool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
    onPressed: mouse => {
      toolbar.swatchesOpen = false;
      editor.commitText();
      if (mouse.button === Qt.RightButton) Capture.State.setLiveTool("");
      else editor.press(Qt.point(mouse.x, mouse.y));
    }
    onPositionChanged: mouse => {
      if (pressed) editor.drag(Qt.point(mouse.x, mouse.y), mouse.modifiers & Qt.ShiftModifier);
    }
    onReleased: mouse => {
      if (mouse.button === Qt.LeftButton) editor.release();
    }
  }

  Capture.Toolbar {
    id: toolbar
    anchors.fill: parent
    mode: "live"
    opened: root.toolbarHere
    barX: root.spot && root.spot.x >= 0 ? root.spot.x : -1
    barY: root.spot && root.spot.y >= 0 ? root.spot.y : -1
    swatchesBelow: root.spot ? root.spot.below : false
    shadows: []
    tool: Capture.State.liveTool
    color: Capture.State.liveColor
    canUndo: Capture.State.liveHistory.length > 0
    fading: Capture.State.liveFade
    onToolPicked: name => Capture.State.setLiveTool(name)
    onColorPicked: index => Capture.State.pickLiveColor(index)
    onUndoClicked: Capture.State.liveUndo()
    onClearClicked: Capture.State.clearDrawing()
    onFadeClicked: Capture.State.liveFade = !Capture.State.liveFade
  }
}
