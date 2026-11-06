pragma Singleton
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// The default drawing colour: `accent` in ~/.config/lilypad/config.json.
Singleton {
  id: root
  readonly property color fallback: "#B0FF4F"
  property color color: fallback

  FileView {
    path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/lilypad/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.color = JSON.parse(text()).accent || root.fallback;
      } catch (error) { console.warn("Could not read accent colour:", error); }
    }
  }
}
