pragma Singleton
import QtQuick

QtObject {
  // Frosted glass: a dark tint, so white text stays readable over white windows.
  readonly property color cardFill: Qt.rgba(29 / 255, 29 / 255, 29 / 255, 0.72)
  readonly property color outline: Qt.rgba(1, 1, 1, 0.10)
  readonly property color controlHover: Qt.rgba(1, 1, 1, 0.04)
  readonly property color controlPressed: Qt.rgba(1, 1, 1, 0.10)
  readonly property int radius: 16
  readonly property int openDuration: 140
  readonly property string fontFamily: "Segoe UI Variable"
  readonly property var controlShadows: [
    { x: 0, y: 97, blur: 33.5, alpha: 0.04 },
    { x: 0, y: 47, blur: 27.5, alpha: 0.06 },
    { x: 0, y: 12, blur: 24.5, alpha: 0.10 },
    { x: 0, y: 11, blur: 23, alpha: 0.13 },
    { x: 0, y: 9, blur: 10, alpha: 0.15 }
  ]
}
