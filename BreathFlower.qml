import QtQuick

// Breath pacer as a six-petal flower (Apple-Breathe style): petals open on the inhale,
// hold, close on the exhale. Phase word + seconds left. Overlays any visual.
Item {
  id: root
  property real level: 0            // 0..1 openness from the pacer clock
  property string word: ""          // in · hold · out · hold
  property real secondsLeft: 0
  property color petal: "#7FB7C9"
  property color petal2: "#F2C063"
  property color ink: "#E8E4D9"
  property bool compact: false      // small corner version for the panel strip
  readonly property real d: Math.min(width, height)
  clip: true

  Item {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -root.d * 0.06
    width: root.d * 0.9; height: root.d * 0.9
    rotation: root.level * 60
    Behavior on rotation { NumberAnimation { duration: 120 } }
    Repeater {
      model: 6
      delegate: Rectangle {
        required property int index
        readonly property real open: 0.18 + 0.20 * root.level        // diameter fraction: 0.18..0.38
        readonly property real dd: root.d * 0.9
        width: dd * open; height: width; radius: width / 2
        x: dd / 2 - width / 2 + Math.cos(index * Math.PI / 3) * dd * (0.05 + 0.22 * root.level)   // offset + radius ≤ 0.46 dd
        y: dd / 2 - height / 2 + Math.sin(index * Math.PI / 3) * dd * (0.05 + 0.22 * root.level)
        color: Qt.rgba(root.petal.r, root.petal.g, root.petal.b, 0.28 + 0.22 * root.level)
        border.width: 1; border.color: Qt.rgba(root.petal2.r, root.petal2.g, root.petal2.b, 0.35)
        Behavior on width { NumberAnimation { duration: 90 } }
        Behavior on x { NumberAnimation { duration: 90 } }
        Behavior on y { NumberAnimation { duration: 90 } }
      }
    }
    Rectangle { anchors.centerIn: parent; width: root.d * 0.9 * (0.10 + 0.10 * root.level); height: width; radius: width / 2; color: Qt.rgba(root.petal2.r, root.petal2.g, root.petal2.b, 0.55) }
  }
  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.compact ? 2 : root.d * 0.02
    spacing: 0
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.word === "in" ? "breathe in" : root.word === "out" ? "breathe out" : root.word; color: root.ink; font.pixelSize: root.compact ? 11 : Math.max(16, root.d * 0.06); font.letterSpacing: 2; opacity: 0.9 }
    Text { visible: !root.compact; anchors.horizontalCenter: parent.horizontalCenter; text: root.secondsLeft > 0 ? Math.ceil(root.secondsLeft) : ""; color: root.ink; font.pixelSize: Math.max(12, root.d * 0.04); opacity: 0.6 }
  }
}
