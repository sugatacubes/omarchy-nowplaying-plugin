import QtQuick
import qs.Commons

// Lightweight synthetic circular waveform. MPRIS exposes playback state and
// metadata, not PCM samples, so this visualizes activity instead of pretending
// to be a live spectrum analyzer.
Item {
  id: root

  property bool running: false
  property bool hovered: false
  property bool compact: false
  property int barCount: 12
  property color waveColor: Color.foreground
  property color accentColor: Color.foreground
  property real innerRadiusRatio: compact ? 0.27 : 0.34
  property real maxBarRatio: compact ? 0.14 : 0.16
  property real barWidth: compact ? 1.1 : 2
  property real phase: 0
  property real energy: running ? 1 : 0

  implicitWidth: compact ? Style.bar.iconCanvas : Style.space(104)
  implicitHeight: implicitWidth

  Behavior on energy {
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  NumberAnimation on phase {
    running: root.running && root.visible
    loops: Animation.Infinite
    from: 0
    to: Math.PI * 2
    duration: 1350
    easing.type: Easing.Linear
  }

  Repeater {
    model: Math.max(8, root.barCount)

    delegate: Item {
      id: spoke
      required property int index

      anchors.fill: parent
      transformOrigin: Item.Center
      rotation: index * 360 / Math.max(8, root.barCount)

      readonly property real sample: Math.max(0, Math.min(1,
        0.5
        + 0.32 * Math.sin(root.phase * 2 + index * 1.65)
        + 0.18 * Math.sin(root.phase * 3 - index * 0.73)))
      readonly property real quietHeight: root.compact ? 1.4 : Style.spaceReal(3)
      readonly property real pulseHeight: Math.max(0,
        Math.min(root.width, root.height) * root.maxBarRatio * sample * root.energy)
      readonly property real innerRadius: Math.min(root.width, root.height) * root.innerRadiusRatio

      Rectangle {
        width: root.barWidth
        height: spoke.quietHeight + spoke.pulseHeight
        radius: width / 2
        x: (spoke.width - width) / 2
        y: spoke.height / 2 - spoke.innerRadius - height
        color: root.waveColor
        opacity: 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    text: root.running ? "󰍤" : "󰀊"
    color: root.waveColor
    opacity: root.compact ? 1 : 0
    font.family: Style.font.family
    font.pixelSize: root.compact ? Math.max(5, root.width * 0.30) : 0
    visible: root.compact

    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }
}
