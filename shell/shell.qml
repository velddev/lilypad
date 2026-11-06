//@ pragma Env QSG_RENDER_LOOP = threaded
import QtQuick
import Quickshell
import "capture" as Capture

// One toast, region picker and drawing overlay per monitor. bin/lilypad starts this on demand.
ShellRoot {
  Variants {
    model: Quickshell.screens
    delegate: Scope {
      required property var modelData
      Capture.Toast { screen: modelData; outputName: modelData.name }
      Capture.Selector { screen: modelData; outputName: modelData.name }
      Capture.Overlay { screen: modelData; outputName: modelData.name }
    }
  }
}
