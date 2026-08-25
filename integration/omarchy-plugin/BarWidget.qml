import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

BarWidget {
  id: root
  moduleName: "bmw.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property var stockPlayer: mediaService ? mediaService.activePlayer : null
  readonly property var currentPlayer: stockPlayer
  readonly property string currentKey: mediaService && currentPlayer ? mediaService.playerKey(currentPlayer) : ""
  readonly property string applePlayerKey: MediaController.applePlayerKey(sourcePlayers, applePids)

  property var applePids: []
  property string manualPlayerKey: ""
  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property real maxLabelWidth: 250
  property real lastAudibleVolume: 0.7

  property string sleepMode: ""
  property double sleepDeadlineMs: 0
  property string sleepPlayerKey: ""
  property string sleepTrackSignature: ""
  property double sleepNowMs: Date.now()

  readonly property bool hasPlayer: currentPlayer !== null
  readonly property bool hasMedia: hasPlayer && !!(currentPlayer.trackTitle || currentPlayer.trackArtist)
  readonly property string title: hasMedia ? String(currentPlayer.trackTitle || "") : "Apple Music"
  readonly property string artist: hasMedia ? String(currentPlayer.trackArtist || "") : "Open to start playback"
  readonly property string sourceName: MediaController.sourceName(currentPlayer, applePlayerKey)
  readonly property string artUrl: hasMedia ? String(currentPlayer.trackArtUrl || "") : ""
  readonly property bool playing: hasPlayer && currentPlayer.isPlaying
  readonly property real position: hasPlayer && currentPlayer.positionSupported ? Number(currentPlayer.position || 0) : 0
  readonly property real duration: hasPlayer && currentPlayer.lengthSupported ? Number(currentPlayer.length || 0) : 0
  readonly property real volume: hasPlayer && currentPlayer.volumeSupported ? Number(currentPlayer.volume ?? 1) : 1
  readonly property string sleepLabel: sleepMode === "deadline"
    ? "Sleep in " + MediaController.timerRemaining(sleepDeadlineMs, sleepNowMs)
    : (sleepMode === "track" ? "Sleep at end of track" : "")

  function open() {
    popupOpen = true
    requestAppleProbe()
  }
  function close() { popupOpen = false }

  function playerForKey(key) {
    if (!mediaService || !key) return null
    return mediaService.playerForKey(key)
  }

  function requestAppleProbe() {
    if (!windowProbe.running) windowProbe.running = true
  }

  function applySourcePreference() {
    if (!mediaService) return
    var fallbackKey = stockPlayer ? mediaService.playerKey(stockPlayer) : ""
    var desired = MediaController.choosePlayerKey(sourcePlayers, applePids, manualPlayerKey, fallbackKey)
    var manual = playerForKey(manualPlayerKey)
    if (!manual || !manual.isPlaying) manualPlayerKey = ""
    if (desired && desired !== fallbackKey) mediaService.selectPlayer(desired)
  }

  function selectSource(key) {
    if (!mediaService || !key) return
    manualPlayerKey = key
    mediaService.selectPlayer(key)
  }

  function runAction(action, targetKey) {
    if (!mediaService) return
    mediaService.runAction(action, false, targetKey || currentKey)
  }

  function seekBy(delta) {
    if (!currentPlayer || !currentPlayer.canSeek || !currentPlayer.positionSupported) return
    var maximum = duration > 0 ? duration : Number.MAX_VALUE
    currentPlayer.position = Math.max(0, Math.min(maximum, position + Number(delta || 0)))
  }

  function seekTo(value) {
    if (!currentPlayer || !currentPlayer.canSeek || !currentPlayer.positionSupported) return
    currentPlayer.position = Math.max(0, Math.min(duration, Number(value || 0)))
  }

  function setVolume(value) {
    if (!currentPlayer || !currentPlayer.volumeSupported) return
    var level = Math.max(0, Math.min(1, Number(value || 0)))
    currentPlayer.volume = level
    if (level > 0.01) lastAudibleVolume = level
  }

  function toggleMute() {
    if (!currentPlayer || !currentPlayer.volumeSupported) return
    if (volume > 0.01) {
      lastAudibleVolume = volume
      setVolume(0)
    } else {
      setVolume(Math.max(0.05, lastAudibleVolume))
    }
  }

  function cycleLoop() {
    if (!currentPlayer || !currentPlayer.loopSupported) return
    if (currentPlayer.loopState === MprisLoopState.None) currentPlayer.loopState = MprisLoopState.Playlist
    else if (currentPlayer.loopState === MprisLoopState.Playlist) currentPlayer.loopState = MprisLoopState.Track
    else currentPlayer.loopState = MprisLoopState.None
  }

  function startSleepMinutes(minutes) {
    if (!currentPlayer) return
    sleepMode = "deadline"
    sleepNowMs = Date.now()
    sleepDeadlineMs = MediaController.timerDeadline(minutes, sleepNowMs)
    sleepPlayerKey = currentKey
    sleepTrackSignature = MediaController.trackSignature(currentPlayer)
  }

  function startSleepAtTrackEnd() {
    if (!currentPlayer) return
    sleepMode = "track"
    sleepNowMs = Date.now()
    sleepDeadlineMs = 0
    sleepPlayerKey = currentKey
    sleepTrackSignature = MediaController.trackSignature(currentPlayer)
  }

  function cancelSleepTimer() {
    sleepMode = ""
    sleepDeadlineMs = 0
    sleepPlayerKey = ""
    sleepTrackSignature = ""
  }

  function checkSleepTimer() {
    if (!sleepMode) return
    sleepNowMs = Date.now()
    var target = playerForKey(sleepPlayerKey)
    if (!target) {
      cancelSleepTimer()
      return
    }

    var shouldPause = sleepMode === "deadline"
      ? sleepNowMs >= sleepDeadlineMs
      : MediaController.endOfTrackReached(target, sleepTrackSignature, 1.5)
    if (!shouldPause) return
    if (target.isPlaying) runAction("pause", sleepPlayerKey)
    cancelSleepTimer()
  }

  function openAppleMusic() {
    if (bar) bar.run("omarchy-music")
    popupOpen = false
  }

  visible: true
  implicitWidth: compactSurface.width
  implicitHeight: barSize

  Component.onCompleted: requestAppleProbe()
  onSourcePlayersChanged: {
    requestAppleProbe()
    Qt.callLater(applySourcePreference)
  }
  onApplePidsChanged: Qt.callLater(applySourcePreference)

  Process {
    id: windowProbe
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      id: windowProbeOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applePids = MediaController.appleMusicPids(windowProbeOutput.text || "[]")
      else root.applePids = []
      Qt.callLater(root.applySourcePreference)
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen || root.sleepMode !== ""
    onTriggered: {
      var timerPlayer = root.playerForKey(root.sleepPlayerKey) || root.currentPlayer
      if (timerPlayer && timerPlayer.positionSupported) timerPlayer.positionChanged()
      root.checkSleepTimer()
    }
  }

  IpcHandler {
    target: "bmw-media"
    function open(): string {
      root.open()
      return "ok"
    }
    function close(): string {
      root.close()
      return "ok"
    }
  }

  BorderSurface {
    id: compactSurface
    anchors.centerIn: parent
    width: compactRow.implicitWidth + Style.space(12)
    height: Math.min(root.barSize - Style.space(4), Style.space(30))
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
        }

        Text {
          width: Math.min(root.maxLabelWidth * 0.38, implicitWidth)
          text: root.artist
          color: Qt.darker(root.bar.barForeground, 1.35)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        text: root.playing ? "󰏤" : "󰐊"
        color: root.playing ? Color.accent : Qt.darker(root.bar.barForeground, 1.35)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: compactMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: {
        root.popupOpen = !root.popupOpen
        if (root.popupOpen) root.requestAppleProbe()
      }
      onWheel: function(wheel) {
        if (root.currentPlayer && root.currentPlayer.volumeSupported)
          root.setVolume(root.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
        else if (wheel.angleDelta.y > 0) root.runAction("previous")
        else root.runAction("next")
      }
      onEntered: if (root.bar) root.bar.showTooltip(root,
        (root.hasMedia ? root.title + (root.artist ? " — " + root.artist : "") : "Apple Music · idle")
        + "\nClick: details · Scroll: " + (root.currentPlayer && root.currentPlayer.volumeSupported ? "volume" : "previous/next"))
      onExited: if (root.bar) root.bar.hideTooltip(root)
    }
  }

  PlayerPopup {
    id: details
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    player: root.currentPlayer
    sourcePlayers: root.sourcePlayers
    mediaService: root.mediaService
    applePlayerKey: root.applePlayerKey
    sleepMode: root.sleepMode
    sleepLabel: root.sleepLabel

    onActionRequested: function(action) { root.runAction(action) }
    onSeekRequested: function(value) { root.seekTo(value) }
    onSeekRelativeRequested: function(delta) { root.seekBy(delta) }
    onVolumeRequested: function(value) { root.setVolume(value) }
    onMuteRequested: root.toggleMute()
    onSourceRequested: function(key) { root.selectSource(key) }
    onShuffleRequested: if (root.currentPlayer && root.currentPlayer.shuffleSupported) root.currentPlayer.shuffle = !root.currentPlayer.shuffle
    onLoopRequested: root.cycleLoop()
    onTimerMinutesRequested: function(minutes) { root.startSleepMinutes(minutes) }
    onTimerEndTrackRequested: root.startSleepAtTrackEnd()
    onTimerCancelRequested: root.cancelSleepTimer()
    onOpenAppleMusicRequested: root.openAppleMusic()
    onPopupActivated: root.requestAppleProbe()
  }
}
