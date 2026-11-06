pragma Singleton
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// The accent colour, and the default drawing colour. Set it in ~/.config/lilypad/accent.json
// as {"accent": "#B0FF4F"}.
Singleton {
  id: root
  property color color: "#B0FF4F"

  FileView {
    path: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/lilypad/accent.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const accent = JSON.parse(text()).accent;
        if (accent) root.color = accent;
      } catch (error) { console.warn("Could not read accent colour:", error); }
    }
  }
}
