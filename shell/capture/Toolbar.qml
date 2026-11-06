pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "." as Capture
import ".." as Shell

// The floating annotation toolbar. Fills its window; only the bar and its colour
// strip take input. The host wires it up (tool, colour, undo) and places it:
// bottom centre unless barX/barY say otherwise.
//   image   screenshot picker: Select (picks the region, takes the shot) and drawing
//           tools on the frozen screen
//   record  recording picker: the same without pixelate (the screen keeps moving)
//   live    over a recording: Pointer (drawing off, click-through) instead of Select,
//           plus clear and fade-out, and no cancel
// Glass in daylight: a backdrop (the frozen screen) blurred in here, or with no
// backdrop the compositor's blur behind the window (the host sets blurRegion).
Item {
  id: root

  property Item backdrop: null     // what the glass blurs, when it's in this window
  property bool opened: false
  property bool swatchesOpen: false
  property string mode: "image"
  property string tool: ""
  property color color: "white"
  property bool canUndo: false
  property bool fading: false
  property real barX: -1
  property real barY: -1
  property bool swatchesBelow: false
  property var shadows: Shell.PanelStyle.controlShadows
  readonly property Item barItem: bar
  readonly property Item swatchItem: swatches
  readonly property bool swatchesShown: swatches.visible

  signal toolPicked(string name)
  signal colorPicked(int index)
  signal undoClicked
  signal clearClicked
  signal fadeClicked
  signal cancel

  readonly property int margin: 8
  readonly property int bottomGap: 28
  readonly property var tools: [
    mode === "live" ? { id: "", icon: "pointer" } : { id: "", icon: "select" },
    { id: "pen", icon: "pen" },
    { id: "arrow", icon: "arrow" },
    { id: "line", icon: "line" },
    { id: "rect", icon: "rect" },
    { id: "text", icon: "text" },
    { id: "marker", icon: "marker" }
  ].concat(mode === "image" ? [{ id: "pixelate", icon: "pixelate" }] : [])

  onOpenedChanged: if (!opened) swatchesOpen = false

  Shell.PopoverFade { target: bar; opened: root.opened; fadeOut: false }
  Shell.PopoverFade { target: swatches; opened: root.opened && root.swatchesOpen; fadeOut: false }

  Glass {
    id: bar
    visible: opacity > 0
    opacity: 0
    width: row.implicitWidth + 12
    height: 44
    x: root.barX >= 0 ? root.barX : Math.round((root.width - width) / 2)
    y: root.barY >= 0 ? root.barY : root.height - height - root.bottomGap

    Row {
      id: row
      anchors.centerIn: parent
      spacing: 2

      Repeater {
        model: root.tools
        delegate: Button {
          required property var modelData
          icon: modelData.icon
          selected: root.tool === modelData.id
          onClicked: root.toolPicked(modelData.id)
        }
      }

      Divider {}

      Button {
        id: colorButton
        selected: root.swatchesOpen
        onClicked: root.swatchesOpen = !root.swatchesOpen
        Rectangle {
          anchors.centerIn: parent
          width: 16
          height: 16
          radius: 8
          color: root.color
          border { width: 1; color: Qt.rgba(1, 1, 1, 0.35) }
        }
      }

      Button {
        icon: "undo"
        enabled: root.canUndo
        onClicked: root.undoClicked()
      }

      Button {
        visible: root.mode === "live"
        icon: "clear"
        onClicked: root.clearClicked()
      }

      Button {
        visible: root.mode === "live"
        icon: "fade"
        selected: root.fading
        onClicked: root.fadeClicked()
      }

      Divider { visible: root.mode !== "live" }

      Button {
        visible: root.mode !== "live"
        iconSource: Qt.resolvedUrl("../assets/close.svg")
        onClicked: root.cancel()
      }
    }
  }

  // Colour strip, above the bar (or below it).
  Glass {
    id: swatches
    visible: opacity > 0
    opacity: 0
    width: swatchRow.implicitWidth + 12
    height: 40
    x: Math.max(root.margin, Math.min(root.width - width - root.margin,
                                      bar.x + row.x + colorButton.x + colorButton.width / 2 - width / 2))
    y: root.swatchesBelow ? bar.y + bar.height + 6 : bar.y - 6 - height

    Row {
      id: swatchRow
      anchors.centerIn: parent
      spacing: 2
      Repeater {
        model: Capture.State.palette
        delegate: Item {
          id: swatch
          required property color modelData
          required property int index
          width: 28
          height: 28
          Rectangle {
            anchors.fill: parent
            radius: 9
            color: swatchMouse.pressed ? Shell.PanelStyle.controlPressed
                : swatchMouse.containsMouse ? Shell.PanelStyle.controlHover : "transparent"
            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
          Rectangle {
            anchors.centerIn: parent
            width: 16
            height: 16
            radius: 8
            color: swatch.modelData
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.35) }
          }
          // Ring around the colour in use.
          Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: 11
            color: "transparent"
            border { width: 1.5; color: "white" }
            visible: Qt.colorEqual(root.color, swatch.modelData)
          }
          MouseArea {
            id: swatchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.colorPicked(swatch.index);
              root.swatchesOpen = false;
            }
          }
        }
      }
    }
  }

  component Glass: Item {
    id: glass
    default property alias content: inner.data

    Shell.Shadow {
      anchors.fill: parent
      cornerRadius: Shell.PanelStyle.radius
      shadows: root.shadows
    }
    ClippingRectangle {
      anchors.fill: parent
      radius: Shell.PanelStyle.radius
      color: "transparent"
      visible: root.backdrop !== null
      ShaderEffectSource {
        id: behind
        anchors.fill: parent
        visible: false
        sourceItem: root.backdrop
        sourceRect: Qt.rect(glass.x, glass.y, glass.width, glass.height)
      }
      MultiEffect {
        anchors.fill: parent
        source: behind
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 48
      }
    }
    Rectangle {
      anchors.fill: parent
      radius: Shell.PanelStyle.radius
      color: Shell.PanelStyle.cardFill
      border { width: 1; color: Shell.PanelStyle.outline }
      antialiasing: true
    }
    Item {
      id: inner
      anchors.fill: parent
    }
    // Swallow clicks on the card itself so they never reach the picker below.
    MouseArea {
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.AllButtons
    }
  }

  component Divider: Item {
    width: 9
    height: 32
    Rectangle {
      anchors.centerIn: parent
      width: 1
      height: 18
      color: Shell.PanelStyle.outline
    }
  }

  component Button: Item {
    id: button
    property string icon: ""
    property url iconSource: icon ? Qt.resolvedUrl("../assets/capture/" + icon + ".svg") : ""
    property bool selected: false
    signal clicked
    width: 32
    height: 32
    opacity: enabled ? 1 : 0.35
    Rectangle {
      anchors.fill: parent
      radius: 10
      color: button.selected || mouse.pressed ? Shell.PanelStyle.controlPressed
          : mouse.containsMouse ? Shell.PanelStyle.controlHover : "transparent"
      Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    Image {
      anchors.centerIn: parent
      visible: button.iconSource != ""
      width: 16
      height: 16
      source: button.iconSource
      sourceSize: Qt.size(32, 32)
      opacity: button.selected || mouse.containsMouse ? 1 : 0.6
      Behavior on opacity { Shell.HoverAnimation {} }
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }
}
