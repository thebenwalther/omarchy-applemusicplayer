import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
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
  property color artworkAccent: Color.accent
  property bool dynamicArtworkColor: true
  property bool barProgressEnabled: true
  property bool motionEnabled: true
  property bool trackChangeOsd: false
  property bool rememberSessionHistory: true
  property var recentHistory: []
  property bool copyAvailable: false

  property bool moreOpen: false
  property bool sourcesOpen: false
  property string displayedArtUrl: ""
  property string previousArtUrl: ""
  property real artReveal: 1
  property real metadataReveal: 1

  readonly property bool hasPlayer: player !== null
  readonly property bool hasMedia: hasPlayer && !!(player.trackTitle || player.trackArtist)
  readonly property string selectedKey: mediaService && player ? mediaService.playerKey(player) : ""
  readonly property string sourceName: MediaController.sourceName(player, applePlayerKey)
  readonly property string title: hasMedia ? String(player.trackTitle || "Unknown title") : "Apple Music"
  readonly property string artist: hasMedia ? String(player.trackArtist || "Unknown artist") : "Open Apple Music to start playback"
  readonly property string album: hasMedia ? String(player.trackAlbum || "") : ""
  readonly property string metadataSignature: [title, artist, album].join("\u001f")
  readonly property string artUrl: hasMedia ? String(player.trackArtUrl || "") : ""
  readonly property real position: hasPlayer && player.positionSupported ? Number(player.position || 0) : 0
  readonly property real duration: hasPlayer && player.lengthSupported ? Number(player.length || 0) : 0
  readonly property real volume: hasPlayer && player.volumeSupported ? Number(player.volume ?? 1) : 1
  readonly property var modeCapabilities: MediaController.capabilities(player)
  readonly property bool canSeek: hasPlayer && player.canSeek && player.positionSupported
  readonly property bool canToggle: hasPlayer && (player.canTogglePlaying || player.canPlay || player.canPause)
  readonly property bool showModes: modeCapabilities.shuffle || modeCapabilities.loop
  readonly property string layoutMode: MediaController.layoutMode(contentWidth)
  readonly property bool narrow: layoutMode === "narrow"
  readonly property color popupText: Color.popups.text
  readonly property color mutedText: Qt.darker(Color.popups.text, 1.4)

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
  signal copyRequested(var value)
  signal historyClearRequested()
  signal preferenceRequested(string key, bool value)
  signal openAppleMusicRequested()
  signal popupActivated()

  contentWidth: fittedContentWidth(Style.space(520))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight, Style.space(760))
  borderColor: root.dynamicArtworkColor ? root.artworkAccent : Color.popups.border

  function swapArtwork() {
    if (displayedArtUrl === artUrl) return
    previousArtUrl = displayedArtUrl
    displayedArtUrl = artUrl
    if (!motionEnabled || previousArtUrl === "") {
      artReveal = 1
      previousArtUrl = ""
      return
    }
    artReveal = 0
    artworkTransition.restart()
  }

  onArtUrlChanged: swapArtwork()
  onMetadataSignatureChanged: {
    if (!motionEnabled) return
    metadataReveal = 0
    metadataTransition.restart()
  }
  onMotionEnabledChanged: if (!motionEnabled) {
    artworkTransition.stop()
    metadataTransition.stop()
    artReveal = 1
    metadataReveal = 1
    previousArtUrl = ""
  }
  Component.onCompleted: swapArtwork()

  FocusScope {
    id: keyScope
    anchors.fill: parent
    focus: root.open

    NumberAnimation {
      id: artworkTransition
      target: root
      property: "artReveal"
      from: 0
      to: 1
      duration: 220
      easing.type: Easing.OutCubic
      onFinished: root.previousArtUrl = ""
    }

    NumberAnimation {
      id: metadataTransition
      target: root
      property: "metadataReveal"
      from: 0
      to: 1
      duration: 200
      easing.type: Easing.OutCubic
    }

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
          id: hero
          width: parent.width
          height: root.narrow ? Style.space(166) : Style.space(200)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.popupText, root.artworkAccent)
          borderSpec: Border.flat(Util.alpha(root.artworkAccent, 0.65), Math.max(1, Style.space(1)))
          clip: true

          Image {
            id: backdropSource
            anchors.fill: parent
            source: root.displayedArtUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
          }

          MultiEffect {
            anchors.fill: parent
            source: backdropSource
            visible: root.displayedArtUrl !== "" && backdropSource.status === Image.Ready
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1.25
            saturation: 0.25
            brightness: -0.35
          }

          Rectangle {
            anchors.fill: parent
            color: Util.alpha(Color.popups.background, root.displayedArtUrl === "" ? 0.72 : 0.58)
          }

          Rectangle {
            anchors.fill: parent
            opacity: root.dynamicArtworkColor ? 1 : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.artworkAccent, 0.26) }
              GradientStop { position: 0.72; color: "transparent" }
            }
            Behavior on opacity { enabled: root.motionEnabled; NumberAnimation { duration: 180 } }
          }

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(16)

            BorderSurface {
              id: artworkFrame
              width: parent.height
              height: parent.height
              radius: Style.cornerRadius
              color: Style.selectedFillFor(root.popupText, root.artworkAccent)
              borderSpec: Border.flat(Util.alpha(root.artworkAccent, 0.85), Math.max(1, Style.space(2)))
              clip: true

              Image {
                anchors.fill: parent
                source: root.previousArtUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 1 - root.artReveal
                visible: source !== "" && opacity > 0
              }

              Image {
                anchors.fill: parent
                source: root.displayedArtUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: root.artReveal
                scale: root.motionEnabled ? 0.98 + root.artReveal * 0.02 : 1
                visible: source !== ""
              }

              Text {
                anchors.centerIn: parent
                visible: root.displayedArtUrl === ""
                text: "󰝚"
                color: root.popupText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: parent.width - artworkFrame.width - parent.spacing
              spacing: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.motionEnabled ? 0.35 + root.metadataReveal * 0.65 : 1
              scale: root.motionEnabled ? 0.98 + root.metadataReveal * 0.02 : 1

              Row {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.player && root.player.isPlaying ? root.artworkAccent : root.mutedText
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  width: parent.width - Style.space(14)
                  text: (root.player && root.player.isPlaying ? "NOW PLAYING · " : "") + root.sourceName.toUpperCase()
                  color: root.player && root.player.isPlaying ? root.artworkAccent : root.mutedText
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }
              }

              Text {
                width: parent.width
                text: root.title
                color: root.popupText
                font.family: root.bar.fontFamily
                font.pixelSize: root.narrow ? Style.font.subtitle : Style.font.title
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
              }

              Text {
                width: parent.width
                text: root.artist
                color: root.popupText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.album
                color: root.mutedText
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
            fillColor: root.artworkAccent
            knobColor: root.popupText
            trackColor: Util.alpha(root.popupText, 0.22)
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
              color: root.mutedText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.right: parent.right
              text: "−" + MediaController.formatTime(Math.max(0, root.duration - root.position))
              color: root.mutedText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(9)
          visible: root.hasPlayer

          Button {
            iconText: "󰒮"
            foreground: root.popupText
            accent: root.artworkAccent
            focusable: true
            enabled: root.player && root.player.canGoPrevious
            opacity: enabled ? 1 : 0.35
            tooltipText: "Previous"
            onClicked: root.actionRequested("previous")
          }
          Button {
            text: "−10"
            foreground: root.popupText
            accent: root.artworkAccent
            focusable: true
            enabled: root.canSeek
            opacity: enabled ? 1 : 0.35
            tooltipText: "Back 10 seconds"
            onClicked: root.seekRelativeRequested(-10)
          }
          Button {
            iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
            foreground: root.popupText
            accent: root.artworkAccent
            background: Util.alpha(root.artworkAccent, 0.2)
            bordered: true
            focusable: true
            horizontalPadding: Style.space(17)
            verticalPadding: Style.space(11)
            iconSize: Style.font.iconLarge
            enabled: root.canToggle
            opacity: enabled ? 1 : 0.35
            tooltipText: root.player && root.player.isPlaying ? "Pause" : "Play"
            onClicked: root.actionRequested("playPause")
          }
          Button {
            text: "+10"
            foreground: root.popupText
            accent: root.artworkAccent
            focusable: true
            enabled: root.canSeek
            opacity: enabled ? 1 : 0.35
            tooltipText: "Forward 10 seconds"
            onClicked: root.seekRelativeRequested(10)
          }
          Button {
            iconText: "󰒭"
            foreground: root.popupText
            accent: root.artworkAccent
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
            foreground: root.popupText
            accent: root.artworkAccent
            focusable: true
            selected: root.player && root.player.shuffleSupported && root.player.shuffle
            visible: root.modeCapabilities.shuffle
            onClicked: root.shuffleRequested()
          }
          Button {
            text: root.player && root.player.loopState === MprisLoopState.Track ? "Repeat one" : "Repeat"
            iconText: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
            foreground: root.popupText
            accent: root.artworkAccent
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
            foreground: root.popupText
            accent: root.artworkAccent
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
            fillColor: root.artworkAccent
            knobColor: root.popupText
            trackColor: Util.alpha(root.popupText, 0.22)
            onMoved: function(value) { root.volumeRequested(value) }
            onReleased: function(value) { root.volumeRequested(value) }
            onRightClicked: root.muteRequested()
          }
          Text {
            width: Style.space(42)
            text: Math.round(root.volume * 100) + "%"
            color: root.mutedText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            id: sourceChip
            visible: root.sourcePlayers.length > 1
            text: root.sourceName
            iconText: "󰓃"
            foreground: root.popupText
            accent: root.artworkAccent
            selected: root.sourcesOpen
            focusable: true
            onClicked: root.sourcesOpen = !root.sourcesOpen
          }
          Button {
            id: sleepChip
            visible: root.sleepMode !== ""
            text: root.sleepLabel
            iconText: "󰔛"
            foreground: root.popupText
            accent: root.artworkAccent
            selected: true
            focusable: true
            onClicked: root.moreOpen = true
          }
          Item {
            width: Math.max(0, parent.width
              - (sourceChip.visible ? sourceChip.implicitWidth + parent.spacing : 0)
              - (sleepChip.visible ? sleepChip.implicitWidth + parent.spacing : 0)
              - moreButton.implicitWidth)
            height: 1
          }
          Button {
            id: moreButton
            text: root.moreOpen ? "Less" : "More"
            iconText: root.moreOpen ? "󰅀" : "󰅂"
            foreground: root.popupText
            accent: root.artworkAccent
            focusable: true
            onClicked: root.moreOpen = !root.moreOpen
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(5)
          visible: root.sourcesOpen && root.sourcePlayers.length > 1

          Repeater {
            model: root.sourcePlayers
            Button {
              required property var modelData
              readonly property string key: root.mediaService ? root.mediaService.playerKey(modelData) : ""
              width: contentColumn.width
              text: MediaController.sourceName(modelData, root.applePlayerKey) + " · " + MediaController.sourceDetail(modelData)
              iconText: modelData && modelData.isPlaying ? "󰏤" : "󰐊"
              foreground: root.popupText
              accent: root.artworkAccent
              leftAlign: true
              focusable: true
              selected: key === root.selectedKey
              bordered: selected
              onClicked: {
                root.sourceRequested(key)
                root.sourcesOpen = false
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(7)

          Button {
            width: Math.max(1, (parent.width - parent.spacing) * 0.68)
            text: "Open Apple Music"
            iconText: "󰎆"
            foreground: root.popupText
            accent: root.artworkAccent
            background: Util.alpha(root.artworkAccent, 0.14)
            bordered: true
            focusable: true
            onClicked: root.openAppleMusicRequested()
          }
          Button {
            width: Math.max(1, (parent.width - parent.spacing) * 0.32)
            text: "Copy"
            iconText: "󰆏"
            foreground: root.popupText
            accent: root.artworkAccent
            bordered: true
            focusable: true
            enabled: root.copyAvailable && root.hasMedia
            opacity: enabled ? 1 : 0.35
            tooltipText: root.copyAvailable ? "Copy now playing" : "wl-copy is unavailable"
            onClicked: root.copyRequested(root.player)
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.moreOpen

          PanelSeparator { width: parent.width; foreground: root.popupText }

          Text {
            text: "SLEEP TIMER"
            color: root.mutedText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Row {
            spacing: Style.space(6)
            visible: root.hasPlayer
            Button { text: "15m"; foreground: root.popupText; accent: root.artworkAccent; focusable: true; onClicked: root.timerMinutesRequested(15) }
            Button { text: "30m"; foreground: root.popupText; accent: root.artworkAccent; focusable: true; onClicked: root.timerMinutesRequested(30) }
            Button { text: "60m"; foreground: root.popupText; accent: root.artworkAccent; focusable: true; onClicked: root.timerMinutesRequested(60) }
            Button { text: "End of track"; foreground: root.popupText; accent: root.artworkAccent; focusable: true; onClicked: root.timerEndTrackRequested() }
            Button {
              text: "Off"
              foreground: root.popupText
              accent: root.artworkAccent
              focusable: true
              enabled: root.sleepMode !== ""
              opacity: enabled ? 1 : 0.35
              onClicked: root.timerCancelRequested()
            }
          }

          Text {
            width: parent.width
            text: root.sleepMode === "" ? "Audio fades for five seconds before playback pauses." : root.sleepLabel
            color: root.sleepMode === "" ? root.mutedText : root.artworkAccent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.popupText }

          Row {
            width: parent.width
            Text {
              width: parent.width - clearHistoryButton.implicitWidth - parent.spacing
              text: "RECENT THIS SESSION"
              color: root.mutedText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Button {
              id: clearHistoryButton
              text: "Clear"
              foreground: root.popupText
              accent: root.artworkAccent
              focusable: true
              enabled: root.recentHistory.length > 0
              opacity: enabled ? 1 : 0.35
              onClicked: root.historyClearRequested()
            }
          }

          Text {
            visible: root.recentHistory.length === 0
            text: root.rememberSessionHistory ? "Tracks you play will appear here." : "Session history is turned off."
            color: root.mutedText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.recentHistory.slice(0, 5)
            Button {
              required property var modelData
              width: contentColumn.width
              text: MediaController.copyText(modelData).replace("\n", " · ")
              iconText: "󰆏"
              foreground: root.popupText
              accent: root.artworkAccent
              leftAlign: true
              focusable: true
              enabled: root.copyAvailable
              tooltipText: "Copy track details"
              onClicked: root.copyRequested(modelData)
            }
          }

          PanelSeparator { width: parent.width; foreground: root.popupText }

          Text {
            text: "APPEARANCE & FEEDBACK"
            color: root.mutedText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Toggle {
            width: parent.width
            label: "Artwork colors"
            description: "Tint accents from the current album cover."
            checked: root.dynamicArtworkColor
            foreground: root.popupText
            accent: root.artworkAccent
            onClicked: root.preferenceRequested("dynamicArtworkColor", !root.dynamicArtworkColor)
          }
          Toggle {
            width: parent.width
            label: "Bar progress"
            description: "Show a thin playback rail under the bar pill."
            checked: root.barProgressEnabled
            foreground: root.popupText
            accent: root.artworkAccent
            onClicked: root.preferenceRequested("barProgress", !root.barProgressEnabled)
          }
          Toggle {
            width: parent.width
            label: "Motion"
            description: "Animate artwork, metadata, and progress changes."
            checked: root.motionEnabled
            foreground: root.popupText
            accent: root.artworkAccent
            onClicked: root.preferenceRequested("motionEnabled", !root.motionEnabled)
          }
          Toggle {
            width: parent.width
            label: "Track-change OSD"
            description: "Show title and artist when the song changes."
            checked: root.trackChangeOsd
            foreground: root.popupText
            accent: root.artworkAccent
            onClicked: root.preferenceRequested("trackChangeOsd", !root.trackChangeOsd)
          }
          Toggle {
            width: parent.width
            label: "Session history"
            description: "Remember up to ten tracks until the shell restarts."
            checked: root.rememberSessionHistory
            foreground: root.popupText
            accent: root.artworkAccent
            onClicked: root.preferenceRequested("rememberSessionHistory", !root.rememberSessionHistory)
          }
        }
      }
    }
  }
}
