import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "bmw.media"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))
  readonly property string statePath: runtimeDir + "/omarchy-applemusicplayer/state.json"
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  property var playerState: ({})
  property bool popupOpen: false
  property real maxLabelWidth: 248

  readonly property bool hasNative: playerState && playerState.connected === true && playerState.current
  readonly property bool hasStock: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool hasMedia: hasNative || hasStock
  readonly property string title: hasNative ? (playerState.current.title || "") : (hasStock ? activePlayer.trackTitle || "" : "")
  readonly property string artist: hasNative ? (playerState.current.artist || "") : (hasStock ? activePlayer.trackArtist || "" : "")
  readonly property string album: hasNative ? (playerState.current.album || "") : (hasStock ? activePlayer.trackAlbum || "" : "")
  readonly property string artUrl: hasNative ? (playerState.current.artwork || "") : (hasStock ? activePlayer.trackArtUrl || "" : "")
  readonly property string sourceName: hasNative ? "Apple Music" : (hasStock ? (activePlayer.identity || activePlayer.desktopEntry || "Media") : "Media")
  readonly property bool playing: hasNative ? playerState.playback === "playing" : (hasStock && activePlayer.isPlaying)
  readonly property string playIcon: playing ? "󰏤" : "󰐊"
  readonly property real position: hasNative ? Number(playerState.elapsed || 0)
    : (hasStock && activePlayer.positionSupported ? Number(activePlayer.position || 0) : 0)
  readonly property real duration: hasNative ? Number(playerState.duration || 0)
    : (hasStock && activePlayer.lengthSupported ? Number(activePlayer.length || 0) : 0)
  readonly property real volume: hasNative ? Number(playerState.volume ?? 1)
    : (hasStock && activePlayer.volumeSupported ? Number(activePlayer.volume ?? 1) : 1)
  readonly property bool canSeek: hasNative || (hasStock && activePlayer.canSeek && activePlayer.positionSupported)
  readonly property bool canPrevious: hasNative || (hasStock && activePlayer.canGoPrevious)
  readonly property bool canNext: hasNative || (hasStock && activePlayer.canGoNext)
  readonly property bool canToggle: hasNative || (hasStock && (activePlayer.canTogglePlaying || activePlayer.canPlay || activePlayer.canPause))
  readonly property bool volumeSupported: hasNative || (hasStock && activePlayer.volumeSupported)
  readonly property bool shuffleSupported: hasStock && activePlayer.shuffleSupported
  readonly property bool loopSupported: hasStock && activePlayer.loopSupported
  readonly property bool shuffled: shuffleSupported && activePlayer.shuffle
  readonly property int loopState: loopSupported ? activePlayer.loopState : MprisLoopState.None

  function close() { popupOpen = false }

  function parseState(raw) {
    try { playerState = JSON.parse(String(raw || "{}")) || ({}) }
    catch (error) { playerState = ({}) }
  }

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(total / 60)
    var remainder = total % 60
    return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
  }

  function command(name, value) {
    if (hasNative) {
      var suffix = value === undefined ? "" : " " + String(value)
      if (root.bar) root.bar.run("omarchy-applemusicctl " + name + suffix)
      return
    }
    if (!mediaService || !activePlayer) return
    var key = mediaService.playerKey(activePlayer)
    if (name === "toggle") mediaService.runAction("playPause", false, key)
    else if (name === "next") mediaService.runAction("next", false, key)
    else if (name === "previous") mediaService.runAction("previous", false, key)
  }

  function seekTo(seconds) {
    var target = Math.max(0, Math.min(duration, Number(seconds) || 0))
    if (hasNative) command("seek", target)
    else if (canSeek) activePlayer.position = target
  }

  function setVolume(level) {
    var target = Math.max(0, Math.min(1, Number(level) || 0))
    if (hasNative) command("volume", target)
    else if (volumeSupported) activePlayer.volume = target
  }

  function cycleLoop() {
    if (!loopSupported) return
    if (activePlayer.loopState === MprisLoopState.None) activePlayer.loopState = MprisLoopState.Playlist
    else if (activePlayer.loopState === MprisLoopState.Playlist) activePlayer.loopState = MprisLoopState.Track
    else activePlayer.loopState = MprisLoopState.None
  }

  function openAppleMusic() {
    if (root.bar) root.bar.run("omarchy-music")
    root.popupOpen = false
  }

  visible: true
  implicitWidth: compactSurface.width
  implicitHeight: barSize

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseState(text())
    onFileChanged: reload()
    onLoadFailed: root.playerState = ({})
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.playing && root.hasStock && root.activePlayer.positionSupported
    onTriggered: root.activePlayer.positionChanged()
  }

  BorderSurface {
    id: compactSurface
    anchors.centerIn: parent
    width: compactRow.implicitWidth + Style.space(12)
    height: Math.min(root.barSize - Style.space(4), Style.space(28))
    radius: height / 2
    color: root.popupOpen ? Style.selectedFillFor(root.bar.foreground, Color.accent)
      : compactMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent)
      : "transparent"
    borderSpec: root.popupOpen ? Border.controlSpec("selected", root.bar.foreground, Color.accent) : Border.none()

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      id: compactRow
      anchors.centerIn: parent
      spacing: Style.space(7)

      BorderSurface {
        width: Math.min(compactSurface.height - Style.space(4), Style.space(24))
        height: width
        radius: Style.space(5)
        color: Style.normalFillFor(root.bar.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
        anchors.verticalCenter: parent.verticalCenter
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
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Item {
        width: root.playing ? Style.space(10) : Style.space(7)
        height: compactSurface.height
        anchors.verticalCenter: parent.verticalCenter

        Row {
          anchors.centerIn: parent
          spacing: 1

          Repeater {
            model: root.playing ? 3 : 1

            Rectangle {
              required property int index
              width: root.playing ? 2 : Style.space(5)
              height: root.playing ? Style.space(4 + ((index + pulse.phase) % 3) * 2) : Style.space(5)
              radius: width / 2
              color: root.playing ? Color.accent : Qt.darker(root.bar.barForeground, 1.45)
              anchors.verticalCenter: parent.verticalCenter

              Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InOutSine } }
            }
          }
        }

        QtObject { id: pulse; property int phase: 0 }
        Timer {
          interval: 220
          repeat: true
          running: root.playing
          onTriggered: pulse.phase = (pulse.phase + 1) % 3
        }
      }

      Row {
        visible: !root.bar.vertical
        spacing: Style.space(5)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: Math.min(root.maxLabelWidth * 0.62, implicitWidth)
          text: root.title
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: Math.min(root.maxLabelWidth * 0.38, implicitWidth)
          text: root.artist
          visible: text !== ""
          color: Qt.darker(root.bar.barForeground, 1.35)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    MouseArea {
      id: compactMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

      onClicked: root.popupOpen = !root.popupOpen
      onWheel: function(wheel) {
        if (root.volumeSupported) root.setVolume(root.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
        else if (wheel.angleDelta.y > 0) root.command("previous")
        else root.command("next")
      }
      onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia
        ? root.title + (root.artist ? " — " + root.artist : "")
          + "\nClick: controls · Scroll: volume"
        : "Apple Music · idle\nClick: controls")
      onExited: if (root.bar) root.bar.hideTooltip(root)
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(popupColumn.implicitHeight)

    Column {
      id: popupColumn
      anchors.fill: parent
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
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(7)
                height: width
                radius: width / 2
                color: root.playing ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.playing ? "NOW PLAYING · " + root.sourceName.toUpperCase() : root.sourceName.toUpperCase()
                color: root.playing ? Color.accent : Qt.darker(root.bar.foreground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
                width: Math.max(1, parent.parent.width - Style.space(18))
              }
            }

            Text {
              text: root.title || "Nothing playing"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.artist
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              text: root.album
              color: Qt.darker(root.bar.foreground, 1.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.duration > 0

        PanelSlider {
          width: parent.width
          bar: root.bar
          value: root.position
          minimum: 0
          maximum: Math.max(1, root.duration)
          step: 5
          enabled: root.canSeek
          opacity: enabled ? 1 : 0.55
          onReleased: function(value) { root.seekTo(value) }
        }

        Item {
          width: parent.width
          height: elapsedText.implicitHeight

          Text {
            id: elapsedText
            anchors.left: parent.left
            text: root.formatTime(root.position)
            color: Qt.darker(root.bar.foreground, 1.45)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            text: root.formatTime(root.duration)
            color: Qt.darker(root.bar.foreground, 1.45)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(8)

        Button {
          iconText: "󰒟"
          foreground: root.bar.foreground
          selected: root.shuffled
          enabled: root.shuffleSupported
          opacity: enabled ? 1 : 0.28
          tooltipText: "Shuffle"
          onClicked: root.activePlayer.shuffle = !root.activePlayer.shuffle
        }

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          enabled: root.canPrevious
          opacity: enabled ? 1 : 0.35
          tooltipText: "Previous"
          onClicked: root.command("previous")
        }

        Button {
          iconText: root.playIcon
          foreground: root.bar.foreground
          background: Style.selectedFillFor(root.bar.foreground, Color.accent)
          bordered: true
          horizontalPadding: Style.space(14)
          verticalPadding: Style.space(9)
          iconSize: Style.font.iconLarge
          enabled: root.canToggle
          opacity: enabled ? 1 : 0.35
          tooltipText: root.playing ? "Pause" : "Play"
          onClicked: root.command("toggle")
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          enabled: root.canNext
          opacity: enabled ? 1 : 0.35
          tooltipText: "Next"
          onClicked: root.command("next")
        }

        Button {
          iconText: root.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
          foreground: root.bar.foreground
          selected: root.loopState !== MprisLoopState.None
          enabled: root.loopSupported
          opacity: enabled ? 1 : 0.28
          tooltipText: root.loopState === MprisLoopState.Track ? "Repeat one" : "Repeat"
          onClicked: root.cycleLoop()
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(10)
        visible: root.volumeSupported

        Text {
          text: root.volume <= 0 ? "󰝟" : (root.volume < 0.5 ? "󰕿" : "󰕾")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.icon
          width: Style.space(20)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
          width: parent.width - Style.space(30)
          bar: root.bar
          value: root.volume
          minimum: 0
          maximum: 1
          step: 0.05
          onMoved: function(value) { root.setVolume(value) }
          onReleased: function(value) { root.setVolume(value) }
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: "MEDIA SOURCES"
          color: Qt.darker(root.bar.foreground, 1.45)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player ? (player.trackTitle || player.trackArtist || "Idle") : "Idle"

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)

                Text {
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }

      Button {
        width: parent.width
        text: "Open Apple Music"
        iconText: "󰎆"
        foreground: root.bar.foreground
        bordered: true
        onClicked: root.openAppleMusic()
      }
    }
  }
}
