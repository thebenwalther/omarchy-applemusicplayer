import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

PopupCard {
  id: root

  property var player: null
  property var sourcePlayers: []
  property var mediaService: null
  property string applePlayerKey: ""
  property string sleepMode: ""
  property string sleepLabel: ""

  readonly property bool hasPlayer: player !== null
  readonly property bool hasMedia: hasPlayer && !!(player.trackTitle || player.trackArtist)
  readonly property string selectedKey: mediaService && player ? mediaService.playerKey(player) : ""
  readonly property string sourceName: MediaController.sourceName(player, applePlayerKey)
  readonly property string title: hasMedia ? String(player.trackTitle || "Unknown title") : "Apple Music"
  readonly property string artist: hasMedia ? String(player.trackArtist || "Unknown artist") : "Open Apple Music to start playback"
  readonly property string album: hasMedia ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: hasMedia ? String(player.trackArtUrl || "") : ""
  readonly property real position: hasPlayer && player.positionSupported ? Number(player.position || 0) : 0
  readonly property real duration: hasPlayer && player.lengthSupported ? Number(player.length || 0) : 0
  readonly property real volume: hasPlayer && player.volumeSupported ? Number(player.volume ?? 1) : 1
  readonly property var modeCapabilities: MediaController.capabilities(player)
  readonly property bool canSeek: hasPlayer && player.canSeek && player.positionSupported
  readonly property bool canToggle: hasPlayer && (player.canTogglePlaying || player.canPlay || player.canPause)
  readonly property bool showModes: modeCapabilities.shuffle || modeCapabilities.loop

  signal actionRequested(string action)
  signal seekRequested(real value)
  signal seekRelativeRequested(real delta)
  signal volumeRequested(real value)
  signal muteRequested()
  signal sourceRequested(string key)
  signal shuffleRequested()
  signal loopRequested()
  signal timerMinutesRequested(int minutes)
  signal timerEndTrackRequested()
  signal timerCancelRequested()
  signal openAppleMusicRequested()
  signal popupActivated()

  contentWidth: fittedContentWidth(Style.space(440))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

  FocusScope {
    id: keyScope
    anchors.fill: parent
    focus: root.open

    Connections {
      target: root
      function onOpenChanged() {
        if (!root.open) return
        root.popupActivated()
        Qt.callLater(function() { keyScope.forceActiveFocus() })
      }
    }

    Keys.onEscapePressed: root.close()
    Keys.onSpacePressed: function(event) {
      if (root.canToggle) root.actionRequested("playPause")
      event.accepted = true
    }
    Keys.onLeftPressed: function(event) {
      if (root.canSeek) root.seekRelativeRequested(-10)
      event.accepted = true
    }
    Keys.onRightPressed: function(event) {
      if (root.canSeek) root.seekRelativeRequested(10)
      event.accepted = true
    }
    Keys.onUpPressed: function(event) {
      if (root.hasPlayer && root.player.volumeSupported) root.volumeRequested(root.volume + 0.05)
      event.accepted = true
    }
    Keys.onDownPressed: function(event) {
      if (root.hasPlayer && root.player.volumeSupported) root.volumeRequested(root.volume - 0.05)
      event.accepted = true
    }

    Flickable {
      id: viewport
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick

      QQC.ScrollBar.vertical: QQC.ScrollBar {
        policy: viewport.contentHeight > viewport.height ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
      }

      Column {
        id: contentColumn
        width: viewport.width - (viewport.contentHeight > viewport.height ? Style.space(8) : 0)
        spacing: Style.space(12)

        BorderSurface {
          width: parent.width
          height: Style.space(148)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(14)

            BorderSurface {
              width: parent.height
              height: parent.height
              radius: Style.cornerRadius
              color: Style.selectedFillFor(root.bar.foreground, Color.accent)
              borderSpec: Border.none()
              clip: true

              Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: root.artUrl
                visible: source !== ""
              }

              Text {
                anchors.centerIn: parent
                visible: root.artUrl === ""
                text: "󰝚"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: parent.width - parent.height - Style.space(14)
              spacing: Style.space(5)
              anchors.verticalCenter: parent.verticalCenter

              Row {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.player && root.player.isPlaying ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  width: parent.width - Style.space(14)
                  text: (root.player && root.player.isPlaying ? "NOW PLAYING · " : "") + root.sourceName.toUpperCase()
                  color: root.player && root.player.isPlaying ? Color.accent : Qt.darker(root.bar.foreground, 1.35)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }
              }

              Text {
                width: parent.width
                text: root.title
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.artist
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.album
                color: Qt.darker(root.bar.foreground, 1.45)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                visible: text !== ""
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: root.hasPlayer && root.duration > 0

          PanelSlider {
            width: parent.width
            bar: root.bar
            value: root.position
            minimum: 0
            maximum: Math.max(1, root.duration)
            step: 5
            enabled: root.canSeek
            opacity: enabled ? 1 : 0.55
            onReleased: function(value) { root.seekRequested(value) }
          }

          Item {
            width: parent.width
            height: elapsed.implicitHeight

            Text {
              id: elapsed
              anchors.left: parent.left
              text: MediaController.formatTime(root.position)
              color: Qt.darker(root.bar.foreground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              text: MediaController.formatTime(root.duration)
              color: Qt.darker(root.bar.foreground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(7)
          visible: root.hasPlayer

          Button {
            iconText: "󰒮"
            foreground: root.bar.foreground
            focusable: true
            enabled: root.player && root.player.canGoPrevious
            opacity: enabled ? 1 : 0.35
            tooltipText: "Previous"
            onClicked: root.actionRequested("previous")
          }
          Button {
            text: "−10"
            foreground: root.bar.foreground
            focusable: true
            enabled: root.canSeek
            opacity: enabled ? 1 : 0.35
            tooltipText: "Back 10 seconds"
            onClicked: root.seekRelativeRequested(-10)
          }
          Button {
            iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
            foreground: root.bar.foreground
            background: Style.selectedFillFor(root.bar.foreground, Color.accent)
            bordered: true
            focusable: true
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(9)
            iconSize: Style.font.iconLarge
            enabled: root.canToggle
            opacity: enabled ? 1 : 0.35
            tooltipText: root.player && root.player.isPlaying ? "Pause" : "Play"
            onClicked: root.actionRequested("playPause")
          }
          Button {
            text: "+10"
            foreground: root.bar.foreground
            focusable: true
            enabled: root.canSeek
            opacity: enabled ? 1 : 0.35
            tooltipText: "Forward 10 seconds"
            onClicked: root.seekRelativeRequested(10)
          }
          Button {
            iconText: "󰒭"
            foreground: root.bar.foreground
            focusable: true
            enabled: root.player && root.player.canGoNext
            opacity: enabled ? 1 : 0.35
            tooltipText: "Next"
            onClicked: root.actionRequested("next")
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)
          visible: root.showModes

          Button {
            text: root.player && root.player.shuffle ? "Shuffle on" : "Shuffle"
            iconText: "󰒟"
            foreground: root.bar.foreground
            focusable: true
            selected: root.player && root.player.shuffleSupported && root.player.shuffle
            visible: root.modeCapabilities.shuffle
            onClicked: root.shuffleRequested()
          }
          Button {
            text: root.player && root.player.loopState === MprisLoopState.Track ? "Repeat one" : "Repeat"
            iconText: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
            foreground: root.bar.foreground
            focusable: true
            selected: root.player && root.player.loopSupported && root.player.loopState !== MprisLoopState.None
            visible: root.modeCapabilities.loop
            onClicked: root.loopRequested()
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.hasPlayer && root.player.volumeSupported

          Button {
            iconText: root.volume <= 0.01 ? "󰝟" : (root.volume < 0.5 ? "󰕿" : "󰕾")
            foreground: root.bar.foreground
            focusable: true
            tooltipText: root.volume <= 0.01 ? "Unmute" : "Mute"
            onClicked: root.muteRequested()
          }
          PanelSlider {
            width: parent.width - Style.space(86)
            bar: root.bar
            value: root.volume
            minimum: 0
            maximum: 1
            step: 0.05
            onMoved: function(value) { root.volumeRequested(value) }
            onReleased: function(value) { root.volumeRequested(value) }
            onRightClicked: root.muteRequested()
          }
          Text {
            width: Style.space(42)
            text: Math.round(root.volume * 100) + "%"
            color: Qt.darker(root.bar.foreground, 1.25)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator {
          visible: root.hasPlayer
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.hasPlayer

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              text: "SLEEP TIMER"
              color: Qt.darker(root.bar.foreground, 1.35)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width - Style.space(90)
              text: root.sleepLabel
              color: Color.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              horizontalAlignment: Text.AlignRight
            }
          }

          Row {
            spacing: Style.space(5)
            Button { text: "15m"; foreground: root.bar.foreground; focusable: true; onClicked: root.timerMinutesRequested(15) }
            Button { text: "30m"; foreground: root.bar.foreground; focusable: true; onClicked: root.timerMinutesRequested(30) }
            Button { text: "60m"; foreground: root.bar.foreground; focusable: true; onClicked: root.timerMinutesRequested(60) }
            Button { text: "End of track"; foreground: root.bar.foreground; focusable: true; onClicked: root.timerEndTrackRequested() }
            Button {
              text: "Off"
              foreground: root.bar.foreground
              focusable: true
              enabled: root.sleepMode !== ""
              opacity: enabled ? 1 : 0.35
              onClicked: root.timerCancelRequested()
            }
          }
        }

        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(5)
          visible: root.sourcePlayers.length > 1

          Text {
            text: "MEDIA SOURCES"
            color: Qt.darker(root.bar.foreground, 1.45)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Repeater {
            model: root.sourcePlayers
            Button {
              required property var modelData
              readonly property string key: root.mediaService ? root.mediaService.playerKey(modelData) : ""
              width: contentColumn.width
              text: MediaController.sourceName(modelData, root.applePlayerKey) + " · " + MediaController.sourceDetail(modelData)
              iconText: modelData && modelData.isPlaying ? "󰏤" : "󰐊"
              foreground: root.bar.foreground
              leftAlign: true
              focusable: true
              selected: key === root.selectedKey
              bordered: selected
              onClicked: root.sourceRequested(key)
            }
          }
        }

        Button {
          width: parent.width
          text: "Open Apple Music"
          iconText: "󰎆"
          foreground: root.bar.foreground
          bordered: true
          focusable: true
          onClicked: root.openAppleMusicRequested()
        }
      }
    }
  }
}
