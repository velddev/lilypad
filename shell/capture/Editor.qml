pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "." as Capture
import ".." as Shell

// Annotations drawn straight onto one monitor's frozen frame, before a region is
// picked: pen, arrow, line, rect, text, marker (highlighter) and pixelate (redact).
// Tool and colour are shared through Capture.State; undo goes through its history
// so it steps back across monitors in the order things were drawn. bake() writes
// the whole annotated monitor, which pond-capture crops like the plain frame.
// The recording overlay uses it too, over the live screen (channel "live", no
// frame, so no pixelate), where strokes can fade out a few seconds after drawing.
// Pixelated boxes stay at the bottom and highlighter strokes under everything
// else, so marks drawn later never disappear under them.
Item {
  id: editor

  required property string outputName
  property Item frame: null        // the frozen screen, same size as this
  property real pixelScale: 1      // physical pixels per logical pixel
  property string channel: "pick"  // "pick" (the pickers) or "live" (the recording overlay)
  readonly property string owner: outputName + ":" + channel
  property string tool: Capture.State.drawTool
  property color color: Capture.State.drawColor
  property int fadeAfter: 0        // ms a shape stays before fading out; 0 keeps it
  readonly property int fadeDuration: 900
  property double now: 0

  property var ops: []
  property var undone: []
  property var draft: null         // the shape being drawn right now
  property bool baking: false
  readonly property bool drawing: draft !== null
  // Its own flag, not the text box's visibility: the box sits in a layer that is
  // only shown while there's something to show, typing included.
  property bool textOpen: false
  readonly property bool typing: textOpen
  readonly property bool dirty: ops.length > 0 || draft !== null || (typing && textBox.text.trim() !== "")
  readonly property size nativeSize: Qt.size(Math.round(width * pixelScale), Math.round(height * pixelScale))

  readonly property real penWidth: 4
  readonly property real markerWidth: 20
  readonly property real textSize: 22
  readonly property real pixelBlock: 12

  clip: true
  onToolChanged: commitText()

  Connections {
    target: Capture.State
    function onUndoOn(owner) { if (owner === editor.owner) editor.undo(); }
    function onRedoOn(owner) { if (owner === editor.owner) editor.redo(); }
    // A new shape anywhere ends redo everywhere.
    function onOpRecorded(owner) { editor.undone = []; }
    function onCommitTyping() { editor.commitText(); }
    function onCancelTyping() { editor.cancelText(); }
    function onTypeOn(owner, key, modifiers, text) {
      if (owner === editor.owner) editor.typeKey(key, modifiers, text);
    }
  }

  // Fading: shapes keep their birth time; once one is past fadeAfter it fades over
  // fadeDuration and is dropped. Turning fading on starts every shape's clock afresh.
  onFadeAfterChanged: {
    now = Date.now();
    if (fadeAfter > 0) ops = ops.map(op => Object.assign({}, op, { born: now }));
  }
  FrameAnimation {
    running: editor.fadeAfter > 0 && editor.ops.length > 0
    onTriggered: {
      editor.now = Date.now();
      const limit = editor.fadeAfter + editor.fadeDuration;
      if (editor.ops.some(op => editor.now - op.born >= limit))
        editor.ops = editor.ops.filter(op => editor.now - op.born < limit);
    }
  }

  function fadeOf(op) {
    if (!op || fadeAfter <= 0 || op.born === undefined) return 1;
    return Math.max(0, Math.min(1, 1 - (now - op.born - fadeAfter) / fadeDuration));
  }

  // Shapes handed over from another editor (the record picker's).
  function load(list) {
    now = Date.now();
    ops = list.map(op => Object.assign({}, op, { born: now }));
    undone = [];
    for (let i = 0; i < ops.length; ++i) Capture.State.recordOp(owner);
  }

  function reset() {
    ops = [];
    undone = [];
    draft = null;
    textOpen = false;
    textBox.text = "";
  }

  function push(op) {
    op.born = Date.now();
    ops = ops.concat([op]);
    Capture.State.recordOp(owner);
  }

  function undo() {
    if (!ops.length) return;
    undone = undone.concat([ops[ops.length - 1]]);
    ops = ops.slice(0, -1);
  }

  function redo() {
    if (!undone.length) return;
    ops = ops.concat([undone[undone.length - 1]]);
    undone = undone.slice(0, -1);
  }

  function clamp(p) {
    return Qt.point(Math.max(0, Math.min(width, p.x)), Math.max(0, Math.min(height, p.y)));
  }

  // Pointer input, in this item's coordinates.
  function press(p) {
    if (baking) return;
    // A string, not the colour itself: Qt keeps value types read from a property
    // tied to it, so every shape would follow the current colour.
    const color = editor.color.toString();
    p = clamp(p);
    if (tool === "text") startText(p, color);
    else if (tool === "pen" || tool === "marker")
      draft = { type: tool, color: color, points: [p, Qt.point(p.x + 0.01, p.y)] };
    else if (tool === "arrow" || tool === "line" || tool === "rect" || tool === "pixelate")
      draft = { type: tool, color: color, x0: p.x, y0: p.y, x1: p.x, y1: p.y };
  }

  function drag(p, constrain) {
    if (!draft) return;
    p = clamp(p);
    const d = Object.assign({}, draft);
    if (d.type === "pen" || d.type === "marker") {
      const last = d.points[d.points.length - 1];
      if (Math.hypot(p.x - last.x, p.y - last.y) < 1.5) return;
      d.points = d.points.concat([p]);
    } else {
      if (constrain) p = constrained(d, p);
      d.x1 = p.x;
      d.y1 = p.y;
    }
    draft = d;
  }

  // Shift: square boxes, arrows and lines snapped to 45°.
  function constrained(d, p) {
    const dx = p.x - d.x0, dy = p.y - d.y0;
    if (d.type === "arrow" || d.type === "line") {
      const angle = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
      const length = Math.hypot(dx, dy);
      return clamp(Qt.point(d.x0 + Math.cos(angle) * length, d.y0 + Math.sin(angle) * length));
    }
    const side = Math.max(Math.abs(dx), Math.abs(dy));
    return clamp(Qt.point(d.x0 + Math.sign(dx || 1) * side, d.y0 + Math.sign(dy || 1) * side));
  }

  function release() {
    const d = draft;
    draft = null;
    if (!d) return;
    if ((d.type === "arrow" || d.type === "line") && Math.hypot(d.x1 - d.x0, d.y1 - d.y0) < 6) return;
    if ((d.type === "rect" || d.type === "pixelate")
        && (Math.abs(d.x1 - d.x0) < 3 || Math.abs(d.y1 - d.y0) < 3)) return;
    push(d);
  }

  function startText(p, color) {
    textBox.x = Math.min(p.x, Math.max(0, width - 40));
    textBox.y = Math.max(0, Math.min(p.y - textSize * 0.7, height - textSize * 1.4));
    textBox.text = "";
    textBox.color = color;
    textBox.cursorPosition = 0;
    textOpen = true;
    Capture.State.typingOwner = owner;
  }

  function commitText() {
    if (!typing) return;
    const text = textBox.text.replace(/\s+$/, "");
    const color = textBox.color.toString();
    cancelText();
    if (text.trim() !== "")
      push({ type: "text", color: color, x: textBox.x, y: textBox.y, text: text });
  }

  function cancelText() {
    if (!typing) return;
    textOpen = false;
    textBox.text = "";
    if (Capture.State.typingOwner === owner) Capture.State.typingOwner = "";
  }

  // Typing into the label. Keys come through Capture.State from whichever monitor
  // niri gave the keyboard to, so the text box never needs focus itself.
  function typeKey(key, modifiers, text) {
    const at = textBox.cursorPosition;
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (modifiers & Qt.ShiftModifier) textBox.insert(at, "\n");
      else commitText();
    } else if (key === Qt.Key_Backspace) {
      if (at > 0) textBox.remove(at - 1, at);
    } else if (key === Qt.Key_Delete) {
      textBox.remove(at, at + 1);
    } else if (key === Qt.Key_Left) {
      textBox.cursorPosition = Math.max(0, at - 1);
    } else if (key === Qt.Key_Right) {
      textBox.cursorPosition = Math.min(textBox.length, at + 1);
    } else if (key === Qt.Key_Home) {
      textBox.cursorPosition = 0;
    } else if (key === Qt.Key_End) {
      textBox.cursorPosition = textBox.length;
    } else if (text.length > 0 && text.charCodeAt(0) >= 32 && !(modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
      textBox.insert(at, text);
    }
  }

  // Render the whole monitor with its annotations at full resolution and save it
  // (PPM: quick to write, and pond-capture crops it like the plain frame).
  function bake(path, done) {
    commitText();
    draft = null;
    baking = true;
    const ok = grabToImage(result => {
      const saved = result.saveToFile(path);
      baking = false;
      done(saved);
    }, nativeSize);
    if (!ok) {
      baking = false;
      done(false);
    }
  }

  // The frozen frame under the annotations, so the bake has it too. Only needed
  // once something is drawn.
  ShaderEffectSource {
    anchors.fill: parent
    visible: editor.dirty && editor.frame !== null
    sourceItem: editor.frame
    textureSize: editor.nativeSize
    smooth: false
  }

  Repeater {
    model: editor.ops.filter(op => op.type === "pixelate")
    delegate: Pixelated { required property var modelData; op: modelData; opacity: editor.fadeOf(modelData) }
  }
  Pixelated { op: editor.draft && editor.draft.type === "pixelate" ? editor.draft : null }

  // Highlighter strokes as one translucent group, so overlaps don't darken.
  Item {
    anchors.fill: parent
    opacity: 0.42
    visible: markers.count > 0 || (editor.draft !== null && editor.draft.type === "marker")
    layer.enabled: visible
    layer.textureSize: editor.nativeSize
    Repeater {
      id: markers
      model: editor.ops.filter(op => op.type === "marker")
      delegate: Stroke { required property var modelData; op: modelData; opacity: editor.fadeOf(modelData) }
    }
    Stroke { op: editor.draft && editor.draft.type === "marker" ? editor.draft : null }
  }

  // Pen, arrows, boxes and text, with a soft shadow so they read on any background.
  Item {
    anchors.fill: parent
    visible: marks.count > 0 || editor.typing || (editor.draft !== null
        && editor.draft.type !== "pixelate" && editor.draft.type !== "marker")
    layer.enabled: visible
    layer.textureSize: editor.nativeSize
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "black"
      shadowOpacity: 0.4
      shadowBlur: 0.3
      shadowVerticalOffset: 1.5
      blurMax: 12
    }
    Repeater {
      id: marks
      model: editor.ops.filter(op => op.type !== "pixelate" && op.type !== "marker")
      delegate: Mark { required property var modelData; op: modelData; opacity: editor.fadeOf(modelData) }
    }
    Mark {
      op: editor.draft && editor.draft.type !== "pixelate" && editor.draft.type !== "marker"
          ? editor.draft : null
    }

    TextEdit {
      id: textBox
      visible: editor.textOpen
      width: Math.max(implicitWidth, 2)
      font { family: Shell.Theme.fontFamily; pixelSize: editor.textSize; weight: Font.DemiBold }
      activeFocusOnPress: false
      cursorVisible: visible
      cursorDelegate: Rectangle { width: 2; color: textBox.color }
      Rectangle {
        anchors { fill: parent; margins: -5 }
        color: "transparent"
        radius: 6
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.55) }
        visible: !editor.baking
      }
    }
  }

  component Stroke: Shape {
    id: stroke
    property var op: null
    anchors.fill: parent
    visible: op !== null
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: stroke.op ? stroke.op.color : "transparent"
      strokeWidth: stroke.op && stroke.op.type === "marker" ? editor.markerWidth : editor.penWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: stroke.op ? stroke.op.points : [] }
    }
  }

  // Arrows, and plain lines (type "line": no head).
  component Arrow: Shape {
    id: arrow
    property var op: null
    readonly property bool headed: op !== null && op.type === "arrow"
    readonly property real length: op ? Math.hypot(op.x1 - op.x0, op.y1 - op.y0) : 0
    readonly property real ux: length > 0 ? (op.x1 - op.x0) / length : 1
    readonly property real uy: length > 0 ? (op.y1 - op.y0) / length : 0
    readonly property real head: headed ? Math.min(length, editor.penWidth * 4.5) : 0
    readonly property real spread: head * 0.62
    readonly property point base: op ? Qt.point(op.x1 - ux * head * 0.8, op.y1 - uy * head * 0.8)
                                     : Qt.point(0, 0)
    anchors.fill: parent
    visible: op !== null
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: arrow.op ? arrow.op.color : "transparent"
      strokeWidth: editor.penWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: arrow.op ? arrow.op.x0 : 0
      startY: arrow.op ? arrow.op.y0 : 0
      PathLine { x: arrow.base.x; y: arrow.base.y }
    }
    ShapePath {
      strokeColor: arrow.headed ? arrow.op.color : "transparent"
      strokeWidth: 1.5
      fillColor: arrow.headed ? arrow.op.color : "transparent"
      joinStyle: ShapePath.RoundJoin
      startX: arrow.op ? arrow.op.x1 : 0
      startY: arrow.op ? arrow.op.y1 : 0
      PathLine {
        x: arrow.op ? arrow.op.x1 - arrow.ux * arrow.head - arrow.uy * arrow.spread : 0
        y: arrow.op ? arrow.op.y1 - arrow.uy * arrow.head + arrow.ux * arrow.spread : 0
      }
      PathLine {
        x: arrow.op ? arrow.op.x1 - arrow.ux * arrow.head + arrow.uy * arrow.spread : 0
        y: arrow.op ? arrow.op.y1 - arrow.uy * arrow.head - arrow.ux * arrow.spread : 0
      }
      PathLine { x: arrow.op ? arrow.op.x1 : 0; y: arrow.op ? arrow.op.y1 : 0 }
    }
  }

  component Mark: Item {
    id: mark
    property var op: null
    anchors.fill: parent
    Stroke { op: mark.op && mark.op.type === "pen" ? mark.op : null }
    Arrow { op: mark.op && (mark.op.type === "arrow" || mark.op.type === "line") ? mark.op : null }
    Rectangle {
      readonly property var op: mark.op && mark.op.type === "rect" ? mark.op : null
      visible: op !== null
      x: op ? Math.min(op.x0, op.x1) : 0
      y: op ? Math.min(op.y0, op.y1) : 0
      width: op ? Math.abs(op.x1 - op.x0) : 0
      height: op ? Math.abs(op.y1 - op.y0) : 0
      radius: 4
      color: "transparent"
      border { width: editor.penWidth; color: op ? op.color : "transparent" }
      antialiasing: true
    }
    Text {
      readonly property var op: mark.op && mark.op.type === "text" ? mark.op : null
      visible: op !== null
      x: op ? op.x + textBox.leftPadding : 0
      y: op ? op.y + textBox.topPadding : 0
      text: op ? op.text : ""
      color: op ? op.color : "transparent"
      font: textBox.font
    }
  }

  // A redacted box: blurred, then blown up in coarse blocks.
  component Pixelated: Item {
    id: box
    property var op: null
    visible: op !== null && width >= 1 && height >= 1
    x: op ? Math.min(op.x0, op.x1) : 0
    y: op ? Math.min(op.y0, op.y1) : 0
    width: op ? Math.abs(op.x1 - op.x0) : 0
    height: op ? Math.abs(op.y1 - op.y0) : 0
    ShaderEffectSource {
      id: under
      width: box.width
      height: box.height
      visible: false
      sourceItem: editor.frame
      sourceRect: Qt.rect(box.x, box.y, box.width, box.height)
    }
    MultiEffect {
      id: blurred
      width: box.width
      height: box.height
      source: under
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1
      blurMax: 24
    }
    ShaderEffectSource {
      anchors.fill: parent
      sourceItem: blurred
      hideSource: true
      smooth: false
      textureSize: Qt.size(Math.max(1, Math.ceil(box.width / editor.pixelBlock)),
                           Math.max(1, Math.ceil(box.height / editor.pixelBlock)))
    }
  }
}
