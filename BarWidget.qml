import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as Local

// Media Halo: a compact now-playing controller for the Omarchy bar.
// Omarchy's built-in service owns MPRIS/PipeWire discovery and selection.
BarWidget {
  id: root
  moduleName: "now-playing.waveform"

  readonly property var mediaService: bar && bar.shell
    ? bar.shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: !!(activePlayer && (activePlayer.isPlaying
    || (mediaService && mediaService.hasMedia)
    || (mediaService && mediaService.playerCanControl(activePlayer))))
  readonly property bool playing: !!(activePlayer && activePlayer.isPlaying)
  readonly property string title: activePlayer
    ? (activePlayer.trackTitle || activePlayer.identity || activePlayer.desktopEntry || "Media") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? (activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
  readonly property string playerName: activePlayer
    ? (activePlayer.identity || activePlayer.desktopEntry || "Media") : ""

  readonly property bool showTitle: setting("showTitle", false)
  readonly property real maxLabelWidth: Math.max(80, Number(setting("maxLabelWidth", 180)))
  readonly property int ringBars: Math.max(8, Math.min(24, Number(setting("ringBars", 12))))

  property bool popupOpen: false

  function close() { popupOpen = false }

  function runAction(action, target) {
    if (!mediaService) return false
    var key = target || playerKey(activePlayer)
    return mediaService.runAction(action, false, key)
  }

  function playerKey(player) {
    return mediaService && player ? mediaService.playerKey(player) : ""
  }

  visible: hasMedia
  opacity: hasMedia ? 1 : 0
  implicitWidth: hasMedia ? contentRow.implicitWidth : 0
  implicitHeight: barSize

  Behavior on opacity {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    BarIconButton {
      id: button
      bar: root.bar
      opticalSize: Math.min(Style.spaceReal(19), Style.bar.iconSlot - Style.spaceReal(4))
      iconComponent: haloIcon
      tooltipText: root.title
        + (root.artist ? " — " + root.artist : "")
        + (root.playing ? "  ·  Playing  ·  Click to pause" : "  ·  Paused  ·  Click to play")

      onPressed: function(b) {
        if (b === Qt.RightButton) root.popupOpen = !root.popupOpen
        else if (b === Qt.MiddleButton) root.runAction("next")
        else root.runAction("playPause")
      }

      onWheelMoved: function(delta) {
        if (delta > 0) root.runAction("previous")
        else if (delta < 0) root.runAction("next")
      }
    }

    Item {
      id: titleClip
      visible: !root.vertical && root.showTitle && root.title !== ""
      width: visible ? Math.min(root.maxLabelWidth, titleLabel.implicitWidth) : 0
      height: button.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: titleLabel
        textFormat: Text.PlainText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        readonly property bool needsScroll: implicitWidth > titleClip.width

        NumberAnimation on x {
          running: titleLabel.needsScroll && !root.popupOpen && root.visible
          loops: Animation.Infinite
          duration: Math.max(6000, titleLabel.implicitWidth * 28)
          from: titleClip.width
          to: -titleLabel.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  Component {
    id: haloIcon

    Local.Waveform {
      running: root.playing
      barCount: root.ringBars
      waveColor: root.bar ? root.bar.barForeground : Color.foreground
      accentColor: root.bar ? root.bar.barForeground : Color.foreground
      hovered: button.tooltipHovered
      compact: true
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(372))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight)

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: Style.space(104)
          height: Style.space(104)

          Local.Waveform {
            anchors.fill: parent
            running: root.playing
            barCount: 28
            innerRadiusRatio: 0.34
            maxBarRatio: 0.16
            barWidth: Style.spaceReal(2)
            waveColor: root.bar ? root.bar.foreground : Color.foreground
            accentColor: root.bar ? root.bar.foreground : Color.foreground
          }

          BorderSurface {
            anchors.centerIn: parent
            width: Style.space(62)
            height: width
            radius: width / 2
            clip: true
            color: Style.normalFillFor(root.bar.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

            Image {
              id: albumArt
              anchors.fill: parent
              anchors.margins: Style.space(2)
              asynchronous: true
              cache: true
              fillMode: Image.PreserveAspectCrop
              source: root.artUrl
              visible: root.artUrl !== "" && status !== Image.Error
            }

            Text {
              anchors.centerIn: parent
              visible: root.artUrl === "" || albumArt.status === Image.Error
              text: root.playing ? "󰍤" : "󰀊"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runAction("playPause")
            }
          }
        }

        Column {
          width: parent.width - Style.space(118)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.artist
            color: Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.72)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.album
            color: Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.52)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: (root.playing ? "PLAYING  ·  " : "PAUSED  ·  ") + root.playerName
            color: root.playing ? Color.accent
              : Util.alpha(root.bar ? root.bar.foreground : Color.foreground, 0.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(7)

        Button {
          iconText: "󰂮"
          foreground: root.bar.foreground
          enabled: !!(root.activePlayer && root.activePlayer.canGoPrevious)
          opacity: enabled ? 1 : 0.35
          onClicked: root.runAction("previous")
        }

        Button {
          iconText: root.playing ? "󰍤" : "󰀊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          iconSize: Style.font.iconLarge
          enabled: !!(root.activePlayer && (root.activePlayer.canTogglePlaying
            || root.activePlayer.canPlay || root.activePlayer.canPause))
          opacity: enabled ? 1 : 0.35
          onClicked: root.runAction("playPause")
        }

        Button {
          iconText: "󰂭"
          foreground: root.bar.foreground
          enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
          opacity: enabled ? 1 : 0.35
          onClicked: root.runAction("next")
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        width: parent.width
        visible: root.sourcePlayers.length > 1
        spacing: Style.space(3)

        Repeater {
          model: root.sourcePlayers

          Button {
            required property var modelData

            width: sourceList.width
            text: (modelData.isPlaying ? "●  " : "○  ")
              + (modelData.trackTitle || modelData.identity || modelData.desktopEntry || "Media source")
            foreground: root.bar.foreground
            active: root.playerKey(modelData) === root.playerKey(root.activePlayer)
            onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.playerKey(modelData))
          }
        }
      }
    }
  }

  IpcHandler {
    target: "now-playing.waveform"

    function open(): void { root.popupOpen = true }
    function close(): void { root.popupOpen = false }
    function show(): void { root.popupOpen = true }
    function hide(): void { root.popupOpen = false }
    function toggle(): void { root.popupOpen = !root.popupOpen }
    function playPause(): void { root.runAction("playPause") }
    function next(): void { root.runAction("next") }
    function previous(): void { root.runAction("previous") }
  }

  onHasMediaChanged: if (!hasMedia) popupOpen = false
}
