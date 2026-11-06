pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "." as Capture
import ".." as Shell

// Frozen-screen region picker. Shows the screen exactly as it was, outlines
// the biggest element under the cursor (usually its window; scroll to step
// into smaller ones), and only darkens the rest once a region is chosen.
//   click        take the outlined element (or the whole monitor)
//   drag         take a custom region
//   scroll       up into smaller / down out to bigger elements
//   Enter        take the outlined element
//   Esc / right  cancel
// For screenshots and recordings the annotation toolbar (Toolbar + Editor) is up the
// whole time: pick a drawing tool to draw on the frozen screen first, then go back to
// Select (S, or click the tool again) and pick the region. For a screenshot the pick
// takes the shot with the drawing baked in; for a recording the drawings stay up on
// the live overlay (Overlay.qml) and the recording starts. Plain region picks
// (selectMode "region") have no toolbar.
PanelWindow {
  id: root

  readonly property bool active: Capture.State.selecting
  required property string outputName
  readonly property string framePath: Capture.State.runtimeDir + "/freeze-" + outputName + ".ppm"
  readonly property real scale: screen && width > 0 && frame.implicitWidth > 0 ? frame.implicitWidth / width : 1
  readonly property bool annotating: Capture.State.pickerDraws
  readonly property bool screenshot: Capture.State.selectMode === "image"
  readonly property bool drawMode: annotating && Capture.State.drawTool !== ""

  property var regions: []
  property var candidates: []   // elements under the cursor, smallest first
  property int level: 0
  property point cursor: Qt.point(-1, -1)
  property bool dragging: false
  property point dragStart
  property rect selection: Qt.rect(0, 0, 0, 0)
  property bool chosen: false

  readonly property rect hovered: candidates.length > 0
      ? candidates[Math.min(level, candidates.length - 1)] : Qt.rect(0, 0, width, height)
  readonly property rect shown: dragging || chosen ? selection : hovered

  visible: active
  color: "transparent"
  anchors { left: true; right: true; top: true; bottom: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "pond-capture-select"
  WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  onActiveChanged: {
    regions = [];
    candidates = [];
    level = 0;
    dragging = false;
    chosen = false;
    editor.reset();
    cursor = Qt.point(-1, -1);
    if (active) {
      regionFile.reload();
      keys.forceActiveFocus();
    }
  }

  Connections {
    target: Capture.State
    function onEnterOn(output) {
      if (output === root.outputName) root.take(root.shown);
    }
    function onHandOff() {
      if (!editor.ops.length) return;
      const carried = Object.assign({}, Capture.State.carried);
      carried[root.outputName] = editor.ops;
      Capture.State.carried = carried;
    }
  }

  FileView {
    id: regionFile
    path: root.active ? Capture.State.runtimeDir + "/regions-" + root.outputName + ".json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const s = root.scale;
        root.regions = JSON.parse(text()).map(r => Qt.rect(r[0] / s, r[1] / s, r[2] / s, r[3] / s));
        root.updateCandidates();
      } catch (error) {}
    }
  }

  function updateCandidates() {
    if (cursor.x < 0) return;
    const previous = hovered;
    const list = regions.filter(r => cursor.x >= r.x && cursor.x < r.x + r.width
                                  && cursor.y >= r.y && cursor.y < r.y + r.height);
    candidates = list;
    // Keep the same element selected while it still contains the cursor,
    // otherwise start at the biggest one short of the whole monitor.
    const keep = isScreen(previous) ? -1
        : list.findIndex(r => r.x === previous.x && r.y === previous.y
                           && r.width === previous.width && r.height === previous.height);
    let biggest = list.length - 1;
    while (biggest > 0 && isScreen(list[biggest])) --biggest;
    level = keep >= 0 ? keep : Math.max(0, biggest);
  }

  function isScreen(r) {
    return r.width * r.height >= width * height * 0.95;
  }

  function pointerMoved(mouse) {
    cursor = Qt.point(mouse.x, mouse.y);
    if (Capture.State.pointerOutput !== outputName) Capture.State.pointerOutput = outputName;
  }

  function stepLevel(wheel) {
    if (candidates.length < 2) return;
    const step = wheel.angleDelta.y < 0 ? 1 : -1;
    level = Math.max(0, Math.min(candidates.length - 1, level + step));
  }

  // The picked region is the shot. With nothing drawn on this monitor pond-capture
  // crops the frozen frame exactly as before; otherwise the editor writes the
  // annotated monitor and pond-capture crops that instead. For a recording, the
  // drawings move to the live overlay and the region goes back as is.
  function take(rect) {
    if (!active || chosen || editor.baking || rect.width < 2 || rect.height < 2) return;
    selection = Qt.rect(Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height));
    chosen = true;
    if (Capture.State.selectMode === "record") {
      Capture.State.commitTyping();
      Capture.State.startLive(outputName, selection);
      reply("");
      return;
    }
    if (!screenshot || !editor.dirty) {
      reply("");
      return;
    }
    const path = Capture.State.runtimeDir + "/annotated-" + Capture.State.selectionToken + ".ppm";
    editor.bake(path, ok => reply(ok ? path : ""));
  }

  function reply(annotated) {
    const fields = [outputName, selection.x, selection.y, selection.width, selection.height];
    if (annotated) fields.push(annotated);
    Capture.State.finishSelection(fields.join(" "));
  }

  function cancel() {
    if (!editor.baking) Capture.State.finishSelection("cancel");
  }

  // Keys reach whichever picker niri gave the keyboard to (the active monitor's),
  // so anything for a particular monitor goes through Capture.State.
  function handleKey(key, modifiers, text) {
    const state = Capture.State;
    const ctrl = modifiers & Qt.ControlModifier;
    const shift = modifiers & Qt.ShiftModifier;
    if (key === Qt.Key_Escape) cancel();
    else if (annotating && state.typingOwner !== "" && !ctrl) state.typeOn(state.typingOwner, key, modifiers, text);
    else if (key === Qt.Key_Return || key === Qt.Key_Enter)
      state.enterOn(annotating && state.pointerOutput !== "" ? state.pointerOutput : outputName);
    else if (!annotating) return false;
    else if (ctrl && key === Qt.Key_Z) shift ? state.redo() : state.undo();
    else if (ctrl && key === Qt.Key_Y) state.redo();
    else if (!ctrl && key === Qt.Key_S) state.drawTool = "";
    else if (!ctrl && toolKeys[key] && (screenshot || toolKeys[key] !== "pixelate")) state.toggleTool(toolKeys[key]);
    else if (!ctrl && key >= Qt.Key_1 && key <= Qt.Key_9) state.pickColor(key - Qt.Key_1);
    else return false;
    return true;
  }

  readonly property var toolKeys: ({
    [Qt.Key_P]: "pen", [Qt.Key_A]: "arrow", [Qt.Key_L]: "line", [Qt.Key_R]: "rect",
    [Qt.Key_T]: "text", [Qt.Key_H]: "marker", [Qt.Key_B]: "pixelate"
  })

  // What the toolbar's glass blurs: the frozen screen, drawings and dimming.
  Item {
    id: backdrop
    anchors.fill: parent

    Image {
      id: frame
      anchors.fill: parent
      source: root.active ? "file://" + root.framePath : ""
      cache: false
      smooth: false
      asynchronous: false
    }

    // Drawings sit on the frame, under the dimming of a region being dragged out.
    Capture.Editor {
      id: editor
      anchors.fill: parent
      visible: root.annotating
      outputName: root.outputName
      frame: frame
      pixelScale: root.scale
    }

    // Darken everything outside the chosen region, only once there is one.
    Item {
      anchors.fill: parent
      visible: root.dragging || root.chosen
      readonly property color shade: Qt.rgba(0, 0, 0, 0.5)
      Rectangle { color: parent.shade; x: 0; y: 0; width: parent.width; height: root.shown.y }
      Rectangle {
        color: parent.shade; x: 0; y: root.shown.y + root.shown.height
        width: parent.width; height: parent.height - y
      }
      Rectangle { color: parent.shade; x: 0; y: root.shown.y; width: root.shown.x; height: root.shown.height }
      Rectangle {
        color: parent.shade; x: root.shown.x + root.shown.width; y: root.shown.y
        width: parent.width - x; height: root.shown.height
      }
    }
  }

  // Outline: hovered element or the region being dragged. Hidden while drawing.
  Rectangle {
    visible: root.cursor.x >= 0 && !editor.drawing && (root.dragging || root.chosen || root.candidates.length > 0)
    x: root.shown.x - 1
    y: root.shown.y - 1
    width: root.shown.width + 2
    height: root.shown.height + 2
    color: "transparent"
    border.width: 1
    border.color: "white"
    opacity: root.drawMode && !root.chosen ? 0.4 : 1
    Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !root.dragging; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: !root.dragging; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
  }

  // Size label
  Rectangle {
    visible: root.cursor.x >= 0 && !root.chosen && !root.drawMode
    readonly property bool below: root.shown.y + root.shown.height + height + 8 < root.height
    x: Math.max(4, Math.min(root.width - width - 4, root.shown.x))
    y: below ? root.shown.y + root.shown.height + 6 : Math.max(4, root.shown.y - height - 6)
    width: sizeText.implicitWidth + 14
    height: 22
    radius: 6
    color: "#e61d1d1d"
    Text {
      id: sizeText
      anchors.centerIn: parent
      text: Math.round(root.shown.width * root.scale) + " × " + Math.round(root.shown.height * root.scale)
          + (root.candidates.length > 1 && !root.dragging
             ? "   ·   " + (Math.min(root.level, root.candidates.length - 1) + 1) + "/" + root.candidates.length : "")
      color: "white"
      font { family: Shell.Theme.fontFamily; pixelSize: 12; weight: Font.Medium; features: { "tnum": 1 } }
    }
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: event => {
      event.accepted = root.handleKey(event.key, event.modifiers, event.text);
    }
  }

  // Picking: hover, click, drag, scroll.
  MouseArea {
    anchors.fill: parent
    enabled: !root.drawMode
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.CrossCursor
    onContainsMouseChanged: if (containsMouse) root.pointerMoved({ x: mouseX, y: mouseY })
    onPositionChanged: mouse => {
      root.pointerMoved(mouse);
      if (pressed && (mouse.buttons & Qt.LeftButton)) {
        if (!root.dragging && Math.hypot(mouse.x - root.dragStart.x, mouse.y - root.dragStart.y) > 4)
          root.dragging = true;
        if (root.dragging) {
          const x0 = Math.max(0, Math.min(root.dragStart.x, mouse.x));
          const y0 = Math.max(0, Math.min(root.dragStart.y, mouse.y));
          const x1 = Math.min(root.width, Math.max(root.dragStart.x, mouse.x));
          const y1 = Math.min(root.height, Math.max(root.dragStart.y, mouse.y));
          root.selection = Qt.rect(x0, y0, x1 - x0, y1 - y0);
        }
      } else root.updateCandidates();
    }
    onPressed: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.cancel();
        return;
      }
      toolbar.swatchesOpen = false;
      Capture.State.commitTyping();
      root.dragStart = Qt.point(mouse.x, mouse.y);
    }
    onReleased: mouse => {
      if (mouse.button !== Qt.LeftButton) return;
      root.take(root.dragging ? root.selection : root.hovered);
      root.dragging = false;
    }
    onWheel: wheel => root.stepLevel(wheel)
  }

  // Drawing, while a tool is picked.
  MouseArea {
    anchors.fill: parent
    enabled: root.drawMode && !root.chosen && !editor.baking
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Capture.State.drawTool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
    onContainsMouseChanged: if (containsMouse) root.pointerMoved({ x: mouseX, y: mouseY })
    onPressed: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.cancel();
        return;
      }
      toolbar.swatchesOpen = false;
      Capture.State.commitTyping();
      editor.press(Qt.point(mouse.x, mouse.y));
    }
    onPositionChanged: mouse => {
      root.pointerMoved(mouse);
      if (pressed) editor.drag(Qt.point(mouse.x, mouse.y), mouse.modifiers & Qt.ShiftModifier);
      else root.updateCandidates();
    }
    onReleased: mouse => {
      if (mouse.button === Qt.LeftButton) editor.release();
    }
    onWheel: wheel => root.stepLevel(wheel)
  }

  Capture.Toolbar {
    id: toolbar
    anchors.fill: parent
    backdrop: backdrop
    mode: root.screenshot ? "image" : "record"
    tool: Capture.State.drawTool
    color: Capture.State.drawColor
    canUndo: Capture.State.history.length > 0 || Capture.State.typingOwner !== ""
    onToolPicked: name => Capture.State.drawTool = name
    onColorPicked: index => Capture.State.pickColor(index)
    onUndoClicked: Capture.State.undo()
    // Out of the way while a region or a shape is being dragged out.
    opened: root.active && root.annotating && !root.chosen && !root.dragging && !editor.drawing
        && (Capture.State.pointerOutput === root.outputName || Capture.State.pointerOutput === "")
    onCancel: root.cancel()
  }
}
