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
  property real lastAudibleVolume: 0.7

  property string sleepMode: ""
  property double sleepDeadlineMs: 0
  property string sleepPlayerKey: ""
  property string sleepTrackSignature: ""
  property double sleepNowMs: Date.now()
  property bool sleepFadeActive: false
  property real sleepFadeOriginalVolume: 1

  readonly property bool dynamicArtworkColor: setting("dynamicArtworkColor", true) === true
  readonly property bool barProgressEnabled: setting("barProgress", true) === true
  readonly property string barDisplayMode: MediaController.normalizeBarDisplayMode(setting("barDisplayMode", "full"))
  readonly property string effectiveBarDisplayMode: bar && bar.vertical ? "compact" : barDisplayMode
  readonly property bool motionEnabled: setting("motionEnabled", true) === true
  readonly property bool trackChangeOsd: setting("trackChangeOsd", false) === true
  readonly property bool rememberSessionHistory: setting("rememberSessionHistory", true) === true
  property color artworkAccent: Color.accent
  property string paletteArtUrl: ""
  property var recentHistory: []
  property string observedTrackSignature: ""
  property bool copyAvailable: false
  readonly property color themeAccent: Color.accent
  readonly property color themePopupBackground: Color.popups.background

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
    ? (sleepFadeActive ? "Fading out" : "Sleep in " + MediaController.timerRemaining(sleepDeadlineMs, sleepNowMs))
    : (sleepMode === "track" ? (sleepFadeActive ? "Fading at track end" : "Sleep at end of track") : "")

  function open() {
    popupOpen = true
    details.resetForOpen()
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

  function updatePreference(key, value) {
    var entry = { id: moduleName }
    for (var name in settings) if (name !== "id") entry[name] = settings[name]
    entry[key] = value
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
    if (key === "rememberSessionHistory" && value !== true) recentHistory = []
    if (key === "dynamicArtworkColor" && value !== true) artworkAccent = Color.accent
  }

  function refreshArtworkAccent() {
    if (!dynamicArtworkColor) {
      artworkAccent = themeAccent
      return
    }
    var update = MediaController.artworkAccentUpdate(
      artUrl,
      paletteArtUrl,
      artPalette.colors,
      themeAccent,
      themePopupBackground
    )
    if (update.apply) artworkAccent = update.color
  }

  function showOsd(icon, message, duration) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: icon || "media",
      message: message || "",
      duration: duration || 1800
    }))
  }

  function captureCurrentTrack() {
    if (!currentPlayer || !hasMedia) return
    var signature = MediaController.trackSignature(currentPlayer)
    if (!signature || signature === observedTrackSignature) return
    var hadPrevious = observedTrackSignature !== ""
    observedTrackSignature = signature
    if (rememberSessionHistory)
      recentHistory = MediaController.addHistory(recentHistory, currentPlayer, 10, Date.now())
    if (hadPrevious && trackChangeOsd)
      showOsd("media", MediaController.copyText(currentPlayer).split("\n")[0], 1800)
  }

  function clearHistory() { recentHistory = [] }

  function copyMetadata(value) {
    if (!copyAvailable || copyProcess.running) return
    var text = MediaController.copyText(value)
    if (!text) return
    copyProcess.command = ["wl-copy", text]
    copyProcess.running = true
    showOsd("󰆏", "Copied now playing", 1200)
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
    if (sleepFadeActive) cancelSleepTimer()
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
    cancelSleepTimer()
    sleepMode = "deadline"
    sleepNowMs = Date.now()
    sleepDeadlineMs = MediaController.timerDeadline(MediaController.clampSleepMinutes(minutes), sleepNowMs)
    sleepPlayerKey = currentKey
    sleepTrackSignature = MediaController.trackSignature(currentPlayer)
  }

  function startSleepAtTrackEnd() {
    if (!currentPlayer) return
    cancelSleepTimer()
    sleepMode = "track"
    sleepNowMs = Date.now()
    sleepDeadlineMs = 0
    sleepPlayerKey = currentKey
    sleepTrackSignature = MediaController.trackSignature(currentPlayer)
  }

  function clearSleepTimer(restoreVolume) {
    var target = playerForKey(sleepPlayerKey)
    if (restoreVolume && sleepFadeActive && target && target.volumeSupported)
      target.volume = sleepFadeOriginalVolume
    sleepMode = ""
    sleepDeadlineMs = 0
    sleepPlayerKey = ""
    sleepTrackSignature = ""
    sleepFadeActive = false
    sleepFadeOriginalVolume = 1
  }

  function cancelSleepTimer() { clearSleepTimer(true) }

  function checkSleepTimer() {
    if (!sleepMode) return
    sleepNowMs = Date.now()
    var target = playerForKey(sleepPlayerKey)
    if (!target) {
      cancelSleepTimer()
      return
    }

    var state = MediaController.timerPhase(sleepMode, sleepDeadlineMs, target, sleepTrackSignature, sleepNowMs, 5)
    if (state.phase === "wait" || state.phase === "idle") return
    if (state.phase === "fade") {
      if (!target.volumeSupported) return
      if (!sleepFadeActive) {
        sleepFadeActive = true
        sleepFadeOriginalVolume = Math.max(0, Math.min(1, Number(target.volume || 0)))
      }
      target.volume = MediaController.fadeVolume(sleepFadeOriginalVolume, state.progress)
      return
    }
    if (state.phase !== "finish") return
    if (target.isPlaying) runAction("pause", sleepPlayerKey)
    if (sleepFadeActive && target.volumeSupported) target.volume = sleepFadeOriginalVolume
    showOsd("media-pause", "Sleep timer finished", 1800)
    clearSleepTimer(false)
  }

  function openAppleMusic() {
    if (bar) bar.run("omarchy-music")
    popupOpen = false
  }

  function openAudioPanel() {
    if (!bar || !bar.shell || typeof bar.shell.summon !== "function") {
      showOsd("audio-volume-high", "Audio panel unavailable", 1600)
      return
    }
    if (!bar.shell.summon("omarchy.audio", "{}"))
      showOsd("audio-volume-high", "Audio panel unavailable", 1600)
  }

  visible: true
  implicitWidth: compactSurface.width
  implicitHeight: barSize

  Component.onCompleted: {
    requestAppleProbe()
    copyProbe.running = true
    historyCapture.restart()
  }
  onSourcePlayersChanged: {
    requestAppleProbe()
    Qt.callLater(applySourcePreference)
  }
  onApplePidsChanged: Qt.callLater(applySourcePreference)
  onCurrentPlayerChanged: historyCapture.restart()
  onArtUrlChanged: {
    paletteArtUrl = ""
    if (!artUrl || !dynamicArtworkColor) artworkAccent = themeAccent
  }
  onDynamicArtworkColorChanged: refreshArtworkAccent()
  onThemeAccentChanged: refreshArtworkAccent()
  onThemePopupBackgroundChanged: refreshArtworkAccent()
  onRememberSessionHistoryChanged: if (!rememberSessionHistory) recentHistory = []

  ColorQuantizer {
    id: artPalette
    source: root.dynamicArtworkColor ? root.artUrl : ""
    depth: 4
    rescaleSize: 64
    onColorsChanged: {
      root.paletteArtUrl = String(source || "")
      root.refreshArtworkAccent()
    }
  }

  Behavior on artworkAccent {
    enabled: root.motionEnabled
    ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  Connections {
    target: root.currentPlayer
    function onTrackChanged() { historyCapture.restart() }
    function onPostTrackChanged() { historyCapture.restart() }
    function onMetadataChanged() { historyCapture.restart() }
  }

  Timer {
    id: historyCapture
    interval: 350
    repeat: false
    onTriggered: root.captureCurrentTrack()
  }

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

  Process {
    id: copyProbe
    command: ["sh", "-c", "command -v wl-copy >/dev/null 2>&1"]
    onExited: function(exitCode) { root.copyAvailable = exitCode === 0 }
  }

  Process { id: copyProcess }

  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen || root.sleepMode !== "" || (root.barProgressEnabled && root.playing)
    onTriggered: {
      var timerPlayer = root.playerForKey(root.sleepPlayerKey) || root.currentPlayer
      if (timerPlayer && timerPlayer.positionSupported) timerPlayer.positionChanged()
      root.checkSleepTimer()
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.sleepFadeActive
    onTriggered: root.checkSleepTimer()
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
    color: root.popupOpen ? Style.selectedFillFor(root.bar.foreground, root.artworkAccent)
      : compactMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, root.artworkAccent)
      : "transparent"
    borderSpec: root.popupOpen ? Border.controlSpec("selected", root.bar.foreground, root.artworkAccent) : Border.none()
    clip: true

    Behavior on color { enabled: root.motionEnabled; ColorAnimation { duration: 160 } }

    Row {
      id: compactRow
      anchors.centerIn: parent
      spacing: Style.space(7)

      BorderSurface {
        width: Math.min(compactSurface.height - Style.space(4), Style.space(24))
        height: width
        radius: Style.space(5)
        color: Style.normalFillFor(root.bar.foreground, root.artworkAccent)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, root.artworkAccent)
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
        visible: !root.bar.vertical && root.effectiveBarDisplayMode !== "compact"
        spacing: Style.space(5)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: root.effectiveBarDisplayMode === "full" ? Style.space(142) : Style.space(205)
          text: root.title
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: root.effectiveBarDisplayMode === "full"
          width: Style.space(88)
          text: root.artist
          color: Util.alpha(root.bar.barForeground, 0.68)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        text: root.hasPlayer ? (root.playing ? "󰏤" : "󰐊") : "󰝚"
        color: root.playing ? root.bar.barForeground : Util.alpha(root.bar.barForeground, 0.68)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      height: Math.max(1, Style.space(2))
      width: root.barProgressEnabled && root.duration > 0
        ? parent.width * Math.max(0, Math.min(1, root.position / root.duration)) : 0
      radius: height / 2
      color: root.artworkAccent
      visible: root.barProgressEnabled && root.hasMedia && root.duration > 0
      opacity: root.playing ? 0.95 : 0.55
      Behavior on width {
        enabled: root.motionEnabled
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: compactMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: {
        if (root.popupOpen) root.close()
        else root.open()
      }
      onWheel: function(wheel) {
        if (root.currentPlayer && root.currentPlayer.volumeSupported)
          root.setVolume(root.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
        else if (wheel.angleDelta.y > 0) root.runAction("previous")
        else root.runAction("next")
      }
      onEntered: if (root.bar) root.bar.showTooltip(root,
        (root.hasMedia ? root.title + (root.artist ? " — " + root.artist : "") : "Apple Music · idle")
        + (root.duration > 0 ? "\n" + MediaController.formatTime(root.position) + " / " + MediaController.formatTime(root.duration) : "")
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
    artworkAccent: root.artworkAccent
    dynamicArtworkColor: root.dynamicArtworkColor
    barProgressEnabled: root.barProgressEnabled
    barDisplayMode: root.barDisplayMode
    motionEnabled: root.motionEnabled
    trackChangeOsd: root.trackChangeOsd
    rememberSessionHistory: root.rememberSessionHistory
    recentHistory: root.recentHistory
    copyAvailable: root.copyAvailable

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
    onCopyRequested: function(value) { root.copyMetadata(value) }
    onHistoryClearRequested: root.clearHistory()
    onPreferenceRequested: function(key, value) { root.updatePreference(key, value) }
    onOpenAppleMusicRequested: root.openAppleMusic()
    onOpenAudioRequested: root.openAudioPanel()
    onPopupActivated: root.requestAppleProbe()
  }
}
