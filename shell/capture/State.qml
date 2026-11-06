pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".." as Shell

// Bridge between bin/lilypad and the corner toast.
Singleton {
  id: root
  readonly property string tool: Quickshell.shellDir + "/../bin/lilypad"
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/lilypad"

  // Region picker: lilypad asks for a selection and waits for the reply file.
  property bool selecting: false
  property string selectionToken: ""
  // "image": a screenshot, drawn on before the region is picked. "record": a recording's
  // region, drawn on too; the drawings carry over to the live overlay. "region": just the area.
  property string selectMode: "region"
  readonly property bool pickerDraws: selectMode === "image" || selectMode === "record"

  // Drawing on the frozen screens, shared by every monitor's picker. Each picker keeps
  // its own shapes; history says whose each one is ("DP-1:pick"), for undo.
  property string drawTool: ""          // "" picks a region; pen arrow rect text marker pixelate
  property color drawColor: Shell.Accent.color
  property string pointerOutput: ""     // the monitor showing the toolbar
  property string typingOwner: ""       // the editor with a text label open
  property var history: []
  property var redoHistory: []
  // The accent first (the default), then a fixed set without it.
  readonly property var palette: [Shell.Accent.color].concat(
      ["#FF6B6B", "#FFDC67", "#B0FF4F", "#89B4FA", "#F8F9F9", "#1D1D1D"]
          .filter(c => !Qt.colorEqual(c, Shell.Accent.color)))

  // Drawing over the live screen while recording (Overlay.qml): its own tool,
  // colour and history, so a screenshot taken meanwhile doesn't disturb it.
  property bool liveActive: false       // overlay up: drawings carried over, or recording
  property string liveTool: ""          // "" = drawing off, the overlay is click-through
  property string lastLiveTool: "pen"
  property color liveColor: Shell.Accent.color
  property bool liveFade: false         // strokes fade a few seconds after they're drawn
  property var liveHistory: []
  property var liveRedo: []
  property string recordOutput: ""      // the recorded region, in that monitor's coordinates
  property rect recordRect: Qt.rect(0, 0, 0, 0)
  property var liveToolbarSpot: null    // {output, x, y}; x < 0 means bottom centre
  property var carried: ({})            // monitor -> shapes drawn in the record picker

  signal undoOn(string owner)
  signal redoOn(string owner)
  signal opRecorded(string owner)
  signal commitTyping
  signal cancelTyping
  signal typeOn(string owner, int key, int modifiers, string text)
  signal enterOn(string output)
  signal handOff                        // record pickers: put your drawings in `carried`
  signal clearLive

  function beginSelect(token, mode, output) {
    selectionToken = token;
    selectMode = mode;
    drawTool = "";
    drawColor = Shell.Accent.color;
    pointerOutput = output || "";
    typingOwner = "";
    history = [];
    redoHistory = [];
    selecting = true;
  }

  function toggleTool(name) {
    drawTool = drawTool === name ? "" : name;
  }

  function pickColor(index) {
    if (index < palette.length) drawColor = palette[index];
  }

  function recordOp(owner) {
    if (owner.endsWith(":live")) {
      liveHistory = liveHistory.concat([owner]);
      liveRedo = [];
    } else {
      history = history.concat([owner]);
      redoHistory = [];
    }
    opRecorded(owner);
  }

  function undo() {
    if (typingOwner !== "") {
      cancelTyping();
      return;
    }
    if (!history.length) return;
    const owner = history[history.length - 1];
    history = history.slice(0, -1);
    redoHistory = redoHistory.concat([owner]);
    undoOn(owner);
  }

  function redo() {
    if (!redoHistory.length) return;
    const owner = redoHistory[redoHistory.length - 1];
    redoHistory = redoHistory.slice(0, -1);
    history = history.concat([owner]);
    redoOn(owner);
  }

  function liveUndo() {
    if (!liveHistory.length) return;
    const owner = liveHistory[liveHistory.length - 1];
    liveHistory = liveHistory.slice(0, -1);
    liveRedo = liveRedo.concat([owner]);
    undoOn(owner);
  }

  function setLiveTool(name) {
    if (!liveActive) return;
    liveTool = name;
    if (name) lastLiveTool = name;
  }

  function toggleDrawing() {
    setLiveTool(liveTool ? "" : lastLiveTool);
  }

  function pickLiveColor(index) {
    if (index < palette.length) liveColor = palette[index];
  }

  function clearDrawing() {
    liveHistory = [];
    liveRedo = [];
    clearLive();
  }

  // The record picker chose its region: keep its drawings up as the live overlay.
  function startLive(output, rect) {
    recordOutput = output;
    recordRect = rect;
    liveTool = "";
    liveColor = drawColor;
    liveHistory = [];
    liveRedo = [];
    carried = ({});
    handOff();
    liveActive = true;
  }

  function stopLive() {
    liveActive = false;
    recordOutput = "";
    liveTool = "";
    liveFade = false;
    carried = ({});
    clearDrawing();
  }

  property string path: ""
  property string thumb: ""
  property string kind: "image"
  property string outputName: ""
  property int generation: 0
  property int revision: 0
  property string converting: ""
  property string notice: ""

  property bool recording: false
  property string recordingOutput: ""
  property double recordingSince: 0

  readonly property bool isVideo: kind === "video"
  readonly property string fileName: path.substring(path.lastIndexOf("/") + 1)
  readonly property string extension: fileName.substring(fileName.lastIndexOf(".") + 1).toLowerCase()

  function show(newPath, newThumb, newKind, output) {
    path = newPath;
    thumb = newThumb || newPath;
    kind = newKind || "image";
    outputName = output || "";
    converting = "";
    notice = "";
    ++generation;
  }

  function dismiss() {
    path = "";
    converting = "";
  }

  function act(action, extra) {
    if (!path) return;
    Quickshell.execDetached([tool, action, path].concat(extra || []));
  }

  function flash(text) {
    notice = text;
    noticeTimer.restart();
  }

  function finishSelection(result) {
    if (!selecting) return;
    selecting = false;
    Quickshell.execDetached(["sh", "-c", 'printf "%s\n" "$1" > "$2.tmp" && mv "$2.tmp" "$2"', "_",
        result, runtimeDir + "/selection-" + selectionToken]);
  }

  function record() {
    Quickshell.execDetached([tool, "record"]);
  }

  Timer {
    id: noticeTimer
    interval: 1600
    onTriggered: root.notice = ""
  }

  IpcHandler {
    target: "capture"
    // The token of the picker that's open, or "" (lilypad polls this, so a picker lost
    // to a shell reload cancels its capture at once instead of holding the lock for minutes).
    function selection(): string { return root.selecting ? root.selectionToken : ""; }
    function present(path: string, thumb: string, kind: string, output: string): void {
      root.show(path, thumb, kind, output);
    }
    function recordingStarted(output: string): void {
      root.recordingOutput = output;
      root.recordingSince = Date.now();
      root.recording = true;
      root.liveActive = root.recordOutput !== "";
    }
    function recordingStopped(): void {
      root.recording = false;
      root.stopLive();
    }
    function select(token: string): void { root.beginSelect(token, "region", ""); }
    // output: where to show the toolbar until the pointer moves (the focused monitor).
    function selectImage(token: string, output: string): void { root.beginSelect(token, "image", output); }
    function selectRecord(token: string, output: string): void { root.beginSelect(token, "record", output); }
    // Drawing over a recording: on/off (click-through when off), and wipe it.
    function toggleDraw(): void { root.toggleDrawing(); }
    function clearDraw(): void { root.clearDrawing(); }
    function cancelSelect(): void { root.finishSelection("cancel"); }
    function converting(path: string, format: string): void {
      if (path === root.path) root.converting = format;
    }
    function converted(source: string, result: string): void {
      if (source !== root.path) return;
      root.converting = "";
      if (result) root.show(result, root.thumb, root.kind, root.outputName);
      else root.flash("Conversion failed");
    }
    function refresh(path: string): void {
      if (path === root.path) ++root.revision;
    }
  }
}
