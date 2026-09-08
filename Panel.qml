import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as Local

// Expandable popup panel for the now-playing widget.
//
// Layout (left to right):
//   [ thumbnail ] [ title + source ]  [ circular waveform w/ play/pause ]
//
// Matches the user's current theme via Color/Style singletons. Uses
// BorderSurface / CursorSurface primitives from qs.Ui so it lines up
// visually with Omarchy's other panels (audio, network, power).
Panel {
  id: root
  moduleName: "now-playing.waveform"
  ipcTarget: "now-playing.waveform"
  manageIpc: true

  // ---- Injected by BarWidget via injectPanel() ----
  property var media: null           // MediaState instance from BarWidget
  property var hostWidget: null      // the BarWidget root
  property string anchorTarget: ""   // unused, here for future expansion

  // ---- Convenience references ----
  readonly property var m: media
  readonly property bool mprisConnected: m !== null
  readonly property bool hasMedia: m ? m.hasMedia : false
  readonly property bool isPlaying: m ? m.isPlaying : false
  readonly property string titleText: m ? m.title : ""
  readonly property string artistText: m ? m.artist : ""
  readonly property string sourceText: m ? m.playerSource : ""
  readonly property string artUrl: m ? m.artworkUrl : ""

  // ---- Panel dimensions ----
  // Slightly larger than a typical control panel so the waveform has
  // room to breathe; matches the height of the audio panel for visual
  // consistency.
  readonly property int panelWidth: 540
  readonly property int panelHeight: 160
  readonly property int thumbnailSize: 128
  readonly property int waveformSize: 128

  readonly property color panelBg: Color.popups.background
  readonly property color panelBorder: Color.popups.border
  readonly property color panelText: Color.popups.text

  // Bind the panel's open state back to the host widget so the bar
  // marquee can pause while the user is reading.
  onOpenedChanged: {
    if (hostWidget) hostWidget._panelOpen = opened
  }

  // Surface (the actual layer-shell window) is a KeyboardPanel anchored
  // to the bar widget. The KeyboardPanel gives us outside-click dismissal,
  // keyboard navigation, and a proper layer-shell surface.
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem || root.hostWidget
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: root.panelWidth
    contentHeight: root.panelHeight
    // No focusTarget needed: there's no keyboard nav in this panel.
    // Pressing Escape still closes it (KeyboardPanel handles that).

    // Visual frame
    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.panelBg
      borderWidth: Style.normalBorderWidth
      borderColor: root.panelBorder

      // Three-column layout: thumbnail | text | waveform
      RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(14)
        spacing: Style.space(16)

        // ---- LEFT: Album art / video thumbnail ----
        Item {
          id: thumbContainer
          Layout.preferredWidth: root.thumbnailSize
          Layout.preferredHeight: root.thumbnailSize
          Layout.alignment: Qt.AlignVCenter

          // Cached art loader
          Local.Artwork {
            id: artwork
            anchors.fill: parent
            source: root.artUrl
          }

          // Visible thumbnail (rounded clip)
          Rectangle {
            id: thumb
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.alpha(Color.foreground, 0.08)
            border.width: Style.normalBorderWidth
            border.color: Qt.alpha(Color.foreground, 0.18)
            clip: true
            visible: artwork.localPath !== ""

            Image {
              anchors.fill: parent
              anchors.margins: 0
              source: artwork.localPath
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize: Qt.size(root.thumbnailSize * 2, root.thumbnailSize * 2)
              smooth: true
            }
          }

          // Placeholder when no artwork is available
          Column {
            anchors.centerIn: parent
            spacing: Style.space(4)
            visible: artwork.localPath === ""

            Text {
              text: root.isPlaying ? "󰐊" : "󰐋"
              color: Qt.alpha(Color.foreground, 0.4)
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.display
              anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
              text: "No artwork"
              color: Qt.alpha(Color.foreground, 0.4)
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }
        }

        // ---- CENTER: Title (marquee) + source ----
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: false
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(4)

          // Marquee-scrolling title. The clip is a fixed width, and
          // the inner Text animates from right edge to left edge if
          // the title is wider than the clip. Mirrors the marquee in
          // omarchy.clock and omarchy.media.
          Item {
            id: titleClip
            Layout.fillWidth: true
            Layout.preferredHeight: Style.font.subtitle * 1.4
            clip: true

            Text {
              id: titleText
              textFormat: Text.PlainText
              text: root.titleText || "Nothing playing"
              color: root.panelText
              font.family: bar ? bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideNone
              property bool needsScroll: implicitWidth > titleClip.width

              x: needsScroll ? titleClip.width : 0
              NumberAnimation on x {
                running: titleText.needsScroll && root.opened
                loops: Animation.Infinite
                duration: Math.max(6000, titleText.implicitWidth * 30)
                from: titleClip.width
                to: -titleText.implicitWidth - 20
                easing.type: Easing.Linear
              }
            }
          }

          // Optional artist line
          Text {
            text: root.artistText
            color: Qt.alpha(root.panelText, 0.7)
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            Layout.fillWidth: true
            visible: text !== ""
          }

          // Source label (e.g. "YouTube — Firefox")
          Text {
            text: root.sourceText
            color: Qt.alpha(root.panelText, 0.55)
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            Layout.fillWidth: true
            visible: text !== ""
          }

          // Spacer
          Item { Layout.fillHeight: true }
        }

        // ---- RIGHT: Circular waveform with center play/pause ----
        ColumnLayout {
          Layout.preferredWidth: root.waveformSize
          Layout.preferredHeight: root.waveformSize
          Layout.alignment: Qt.AlignVCenter
          spacing: 0

          Item {
            id: waveformHost
            Layout.preferredWidth: root.waveformSize
            Layout.preferredHeight: root.waveformSize

            Local.Waveform {
              id: wave
              anchors.fill: parent
              tickColor: Color.accent
              pausedTickColor: Qt.darker(Color.foreground, 1.6)
              // Bind energy to isPlaying with a smooth animation. The
              // 220ms cubic ease gives the same settle-to-flat feel on
              // pause that the design spec calls for.
              property real _targetEnergy: root.isPlaying ? 1.0 : 0.0
              energy: _targetEnergy
              Behavior on energy {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
              }
            }

            // Center play/pause button (overlaid on the ring)
            Item {
              anchors.centerIn: parent
              width: 56
              height: 56

              WidgetButton {
                anchors.fill: parent
                bar: root.bar
                text: root.isPlaying ? "󰏤" : "󰐊"
                font.pixelSize: Style.font.heading
                onPressed: root.m ? root.m.togglePlayPause() : null
                enabled: root.m ? root.m.canControl : false
              }
            }
          }
        }
      }
    }

    // Optional: prev/next buttons below the three-column row, in a
    // slim row. Sits at the bottom of the panel and is right-aligned.
    Row {
      id: controlRow
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(10)
      spacing: Style.space(6)
      visible: root.hasMedia

      WidgetButton {
        bar: root.bar
        text: "󰒮"
        onPressed: root.m ? root.m.previous() : null
        enabled: root.m ? root.m.canPrev : false
      }
      WidgetButton {
        bar: root.bar
        text: "󰒭"
        onPressed: root.m ? root.m.next() : null
        enabled: root.m ? root.m.canNext : false
      }
    }
  }
}
