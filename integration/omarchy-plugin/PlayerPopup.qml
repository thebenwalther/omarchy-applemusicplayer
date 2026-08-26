import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
import QtQuick.Window
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "MediaController.js" as MediaController

KeyboardPanel {
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
  property string barDisplayMode: "full"
  property bool motionEnabled: true
  property bool trackChangeOsd: false
  property bool rememberSessionHistory: true
  property var recentHistory: []
  property bool copyAvailable: false

  property string page: "player"
  property bool sourcesOpen: false
  property int customSleepMinutes: 45
  property double historyNowMs: Date.now()
  property string displayedArtUrl: ""
  property string previousArtUrl: ""
  property real artReveal: 1
  property real metadataReveal: 1
  property real pageProgress: page === "more" ? 1 : 0

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
  readonly property color mutedText: Util.alpha(Color.popups.text, 0.68)
  readonly property real activePageHeight: page === "more"
    ? Math.min(moreColumn.implicitHeight, Style.space(640))
    : playerColumn.implicitHeight

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
  signal preferenceRequested(string key, var value)
  signal openAppleMusicRequested()
  signal openAudioRequested()
  signal popupActivated()

  focusTarget: keyScope
  contentWidth: fittedContentWidth(Style.space(520))
  contentHeight: fittedContentHeight(activePageHeight, Style.space(700))

  Behavior on pageProgress {
    enabled: root.motionEnabled
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  function resetForOpen() {
    page = MediaController.normalizePopupPage(page, true)
    sourcesOpen = false
    historyNowMs = Date.now()
  }

  function showMore() {
    sourcesOpen = false
    historyNowMs = Date.now()
    page = "more"
    Qt.callLater(function() { backButton.forceActiveFocus() })
  }

  function showPlayer() {
    page = "player"
    Qt.callLater(function() { moreButton.forceActiveFocus() })
  }

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

  function ensureFocusVisible(item) {
    if (!item || !open) return
    var view = page === "more" ? moreView : playerView
    if (!view || !view.contentItem) return
    var point = item.mapToItem(view.contentItem, 0, 0)
    if (point.y < view.contentY) view.contentY = Math.max(0, point.y - Style.space(12))
    else if (point.y + item.height > view.contentY + view.height)
      view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), point.y + item.height - view.height + Style.space(12))
  }

  onOpenChanged: if (open) {
    resetForOpen()
    popupActivated()
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
    focus: true

    Connections {
      target: keyScope.Window.window
      function onActiveFocusItemChanged() {
        var window = keyScope.Window.window
        if (window) Qt.callLater(function() { root.ensureFocusVisible(window.activeFocusItem) })
      }
    }

    Timer {
      interval: 60000
      repeat: true
      running: root.open && root.page === "more"
      triggeredOnStart: true
      onTriggered: root.historyNowMs = Date.now()
    }

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

    Keys.onEscapePressed: {
      if (root.page === "more") root.showPlayer()
      else root.close()
    }
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

    Item {
      anchors.fill: parent
      clip: true

      Flickable {
        id: playerView
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: playerColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        opacity: 1 - root.pageProgress
        x: -root.pageProgress * width * 0.12
        visible: opacity > 0.01
        interactive: contentHeight > height

        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: playerView.contentHeight > playerView.height ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
        }

        Column {
          id: playerColumn
          width: playerView.width - (playerView.contentHeight > playerView.height ? Style.space(8) : 0)
          spacing: Style.space(12)

          BorderSurface {
            id: hero
            width: parent.width
            height: root.narrow ? Style.space(166) : Style.space(200)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.popupText, root.artworkAccent)
            borderSpec: Border.flat(Util.alpha(root.artworkAccent, 0.38), Math.max(1, Style.space(1)))
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
              blurMultiplier: 1.3
              saturation: 0.32
              brightness: -0.38
            }
            Rectangle { anchors.fill: parent; color: Util.alpha(Color.popups.background, root.displayedArtUrl === "" ? 0.74 : 0.6) }
            Rectangle {
              anchors.fill: parent
              gradient: Gradient {
                GradientStop { position: 0; color: Util.alpha(root.artworkAccent, root.dynamicArtworkColor ? 0.22 : 0.08) }
                GradientStop { position: 0.58; color: "transparent" }
                GradientStop { position: 1; color: Util.alpha(Color.popups.background, 0.26) }
              }
            }

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(16)

              Item {
                width: parent.height
                height: parent.height
                Rectangle {
                  anchors.fill: artworkFrame
                  anchors.margins: -Style.space(4)
                  radius: artworkFrame.radius + Style.space(4)
                  color: Util.alpha(root.artworkAccent, 0.16)
                }
                BorderSurface {
                  id: artworkFrame
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: Style.selectedFillFor(root.popupText, root.artworkAccent)
                  borderSpec: Border.flat(Util.alpha(root.artworkAccent, 0.7), Math.max(1, Style.space(1)))
                  clip: true
                  Image { anchors.fill: parent; source: root.previousArtUrl; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: 1 - root.artReveal; visible: source !== "" && opacity > 0 }
                  Image {
                    id: currentArtwork
                    anchors.fill: parent
                    source: root.displayedArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: root.artReveal
                    scale: root.motionEnabled ? 0.98 + root.artReveal * 0.02 : 1
                    visible: source !== ""
                  }
                  Text { anchors.centerIn: parent; visible: root.displayedArtUrl === "" || currentArtwork.status === Image.Error; text: "󰝚"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.displayLarge }
                  Text {
                    anchors.centerIn: parent
                    visible: currentArtwork.status === Image.Loading
                    text: root.motionEnabled ? "󰑓" : "󰄬"
                    color: root.mutedText
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.iconLarge
                    RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.motionEnabled && currentArtwork.status === Image.Loading }
                  }
                }
              }

              Column {
                width: parent.width - parent.children[0].width - parent.spacing
                spacing: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.motionEnabled ? 0.35 + root.metadataReveal * 0.65 : 1
                scale: root.motionEnabled ? 0.98 + root.metadataReveal * 0.02 : 1
                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Rectangle { width: Style.space(7); height: width; radius: width / 2; color: root.player && root.player.isPlaying ? root.artworkAccent : root.mutedText; anchors.verticalCenter: parent.verticalCenter }
                  Text { width: parent.width - Style.space(14); text: (root.player && root.player.isPlaying ? "NOW PLAYING · " : "") + root.sourceName.toUpperCase(); color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; elide: Text.ElideRight }
                }
                Text { width: parent.width; text: root.title; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: root.narrow ? Style.font.subtitle : Style.font.title; font.bold: true; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                Text { width: parent.width; text: root.artist; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                Text { width: parent.width; text: root.album; color: root.mutedText; visible: text !== ""; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: root.hasPlayer && root.duration > 0
            MediaTimeline {
              width: parent.width
              bar: root.bar
              value: root.position
              maximum: root.duration
              seekable: root.canSeek
              motionEnabled: root.motionEnabled
              accent: root.artworkAccent
              foreground: root.popupText
              onMoved: function(value) { root.seekRequested(value) }
              onReleased: function(value) { root.seekRequested(value) }
            }
            Item {
              width: parent.width
              height: elapsed.implicitHeight
              Text { id: elapsed; anchors.left: parent.left; text: MediaController.formatTime(root.position); color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
              Text { anchors.right: parent.right; text: "−" + MediaController.formatTime(Math.max(0, root.duration - root.position)); color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(9)
            visible: root.hasPlayer
            MediaButton { iconText: "󰒮"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.player && root.player.canGoPrevious; opacity: enabled ? 1 : 0.35; tooltipText: "Previous"; accessibleName: "Previous"; onClicked: root.actionRequested("previous") }
            MediaButton { text: "−10"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.canSeek; opacity: enabled ? 1 : 0.35; tooltipText: "Back 10 seconds"; accessibleName: "Back 10 seconds"; onClicked: root.seekRelativeRequested(-10) }
            MediaButton { iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"; foreground: root.popupText; accent: Color.accent; background: Util.alpha(root.artworkAccent, 0.2); bordered: true; focusable: true; horizontalPadding: Style.space(17); verticalPadding: Style.space(11); iconSize: Style.font.iconLarge; enabled: root.canToggle; opacity: enabled ? 1 : 0.35; tooltipText: root.player && root.player.isPlaying ? "Pause" : "Play"; accessibleName: tooltipText; onClicked: root.actionRequested("playPause") }
            MediaButton { text: "+10"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.canSeek; opacity: enabled ? 1 : 0.35; tooltipText: "Forward 10 seconds"; accessibleName: "Forward 10 seconds"; onClicked: root.seekRelativeRequested(10) }
            MediaButton { iconText: "󰒭"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.player && root.player.canGoNext; opacity: enabled ? 1 : 0.35; tooltipText: "Next"; accessibleName: "Next"; onClicked: root.actionRequested("next") }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)
            visible: root.showModes
            MediaButton { text: root.player && root.player.shuffle ? "Shuffle on" : "Shuffle"; iconText: "󰒟"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.player && root.player.shuffleSupported && root.player.shuffle; visible: root.modeCapabilities.shuffle; onClicked: root.shuffleRequested() }
            MediaButton { text: root.player && root.player.loopState === MprisLoopState.Track ? "Repeat one" : "Repeat"; iconText: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"; foreground: root.popupText; accent: Color.accent; focusable: true; selected: root.player && root.player.loopSupported && root.player.loopState !== MprisLoopState.None; visible: root.modeCapabilities.loop; onClicked: root.loopRequested() }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.hasPlayer && root.player.volumeSupported
            MediaButton { iconText: root.volume <= 0.01 ? "󰝟" : (root.volume < 0.5 ? "󰕿" : "󰕾"); foreground: root.popupText; accent: Color.accent; focusable: true; tooltipText: root.volume <= 0.01 ? "Unmute" : "Mute"; accessibleName: tooltipText; onClicked: root.muteRequested() }
            MediaSlider { width: parent.width - Style.space(86); bar: root.bar; value: root.volume; minimum: 0; maximum: 1; step: 0.05; motionEnabled: root.motionEnabled; fillColor: root.artworkAccent; knobColor: root.popupText; trackColor: Util.alpha(root.popupText, 0.22); accessibleName: "Volume"; accessibleValueText: Math.round(root.volume * 100) + "%"; onMoved: function(value) { root.volumeRequested(value) }; onReleased: function(value) { root.volumeRequested(value) }; onRightClicked: root.muteRequested() }
            Text { width: Style.space(42); text: Math.round(root.volume * 100) + "%"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            MediaButton { id: sourceChip; visible: root.sourcePlayers.length > 1; text: root.sourceName; iconText: "󰓃"; foreground: root.popupText; accent: Color.accent; selected: root.sourcesOpen; focusable: true; onClicked: root.sourcesOpen = !root.sourcesOpen }
            MediaButton { id: sleepChip; visible: root.sleepMode !== ""; text: root.sleepLabel; iconText: "󰔛"; foreground: root.popupText; accent: Color.accent; selected: true; focusable: true; onClicked: root.showMore() }
            Item { width: Math.max(0, parent.width - (sourceChip.visible ? sourceChip.implicitWidth + parent.spacing : 0) - (sleepChip.visible ? sleepChip.implicitWidth + parent.spacing : 0) - moreButton.implicitWidth); height: 1 }
            MediaButton { id: moreButton; text: "More"; iconText: "󰅂"; foreground: root.popupText; accent: Color.accent; focusable: true; accessibleName: "More player options"; onClicked: root.showMore() }
          }

          Column {
            width: parent.width
            spacing: Style.space(5)
            visible: root.sourcesOpen && root.sourcePlayers.length > 1
            Repeater {
              model: root.sourcePlayers
              MediaButton {
                required property var modelData
                readonly property string key: root.mediaService ? root.mediaService.playerKey(modelData) : ""
                width: playerColumn.width
                text: MediaController.sourceName(modelData, root.applePlayerKey) + " · " + MediaController.sourceDetail(modelData)
                iconText: modelData && modelData.isPlaying ? "󰏤" : "󰐊"
                foreground: root.popupText
                accent: Color.accent
                leftAlign: true
                focusable: true
                selected: key === root.selectedKey
                bordered: selected
                onClicked: { root.sourceRequested(key); root.sourcesOpen = false }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(7)
            MediaButton { width: Math.max(1, (parent.width - parent.spacing) * 0.68); text: "Open Apple Music"; iconText: "󰎆"; foreground: root.popupText; accent: Color.accent; background: Util.alpha(root.artworkAccent, 0.14); bordered: true; focusable: true; onClicked: root.openAppleMusicRequested() }
            MediaButton { width: Math.max(1, (parent.width - parent.spacing) * 0.32); text: "Copy"; iconText: "󰆏"; foreground: root.popupText; accent: Color.accent; bordered: true; focusable: true; enabled: root.copyAvailable && root.hasMedia; opacity: enabled ? 1 : 0.35; tooltipText: root.copyAvailable ? "Copy now playing" : "wl-copy is unavailable"; onClicked: root.copyRequested(root.player) }
          }
        }
      }

      Flickable {
        id: moreView
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: moreColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        opacity: root.pageProgress
        x: (1 - root.pageProgress) * width * 0.12
        visible: opacity > 0.01
        interactive: contentHeight > height

        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: moreView.contentHeight > moreView.height ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
        }

        Column {
          id: moreColumn
          width: moreView.width - (moreView.contentHeight > moreView.height ? Style.space(8) : 0)
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(8)
            MediaButton { id: backButton; text: "Back"; iconText: "󰁍"; foreground: root.popupText; accent: Color.accent; focusable: true; accessibleName: "Back to player"; onClicked: root.showPlayer() }
            Column {
              width: parent.width - parent.children[0].implicitWidth - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              Text { width: parent.width; text: "PLAYER OPTIONS"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
              Text { width: parent.width; text: "Session tools and appearance"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.popupText }
          Text { text: "SLEEP TIMER"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          Row {
            spacing: Style.space(6)
            visible: root.hasPlayer
            MediaButton { text: "15m"; foreground: root.popupText; accent: Color.accent; focusable: true; onClicked: root.timerMinutesRequested(15) }
            MediaButton { text: "30m"; foreground: root.popupText; accent: Color.accent; focusable: true; onClicked: root.timerMinutesRequested(30) }
            MediaButton { text: "60m"; foreground: root.popupText; accent: Color.accent; focusable: true; onClicked: root.timerMinutesRequested(60) }
            MediaButton { text: "End of track"; foreground: root.popupText; accent: Color.accent; focusable: true; onClicked: root.timerEndTrackRequested() }
            MediaButton { text: "Off"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.sleepMode !== ""; opacity: enabled ? 1 : 0.35; onClicked: root.timerCancelRequested() }
          }
          Row {
            width: parent.width
            spacing: Style.space(7)
            visible: root.hasPlayer
            Text { id: customLabel; text: "Custom"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            Item { width: Math.max(0, parent.width - customLabel.implicitWidth - minusSleep.implicitWidth - sleepValue.implicitWidth - plusSleep.implicitWidth - startSleep.implicitWidth - parent.spacing * 5); height: 1 }
            MediaButton { id: minusSleep; iconText: "󰅖"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.customSleepMinutes > 5; tooltipText: "Subtract five minutes"; accessibleName: tooltipText; onClicked: root.customSleepMinutes = MediaController.clampSleepMinutes(root.customSleepMinutes - 5) }
            Text { id: sleepValue; text: root.customSleepMinutes + "m"; color: root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            MediaButton { id: plusSleep; iconText: "󰐕"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.customSleepMinutes < 180; tooltipText: "Add five minutes"; accessibleName: tooltipText; onClicked: root.customSleepMinutes = MediaController.clampSleepMinutes(root.customSleepMinutes + 5) }
            MediaButton { id: startSleep; text: "Start"; foreground: root.popupText; accent: Color.accent; bordered: true; focusable: true; onClicked: root.timerMinutesRequested(root.customSleepMinutes) }
          }
          Text { width: parent.width; text: root.sleepMode === "" ? "Audio fades for five seconds before playback pauses." : root.sleepLabel; color: root.sleepMode === "" ? root.mutedText : root.popupText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }

          PanelSeparator { width: parent.width; foreground: root.popupText }
          Row {
            width: parent.width
            Text { width: parent.width - clearHistoryButton.implicitWidth - parent.spacing; text: "RECENT THIS SESSION"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            MediaButton { id: clearHistoryButton; text: "Clear"; foreground: root.popupText; accent: Color.accent; focusable: true; enabled: root.recentHistory.length > 0; opacity: enabled ? 1 : 0.35; onClicked: root.historyClearRequested() }
          }
          Text { visible: root.recentHistory.length === 0; text: root.rememberSessionHistory ? "Tracks you play will appear here." : "Session history is turned off."; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
          Repeater {
            model: root.recentHistory.slice(0, 5)
            MediaButton {
              required property var modelData
              width: moreColumn.width
              text: MediaController.copyText(modelData).replace("\n", " · ") + "  ·  " + MediaController.relativeTime(modelData.timestamp, root.historyNowMs)
              iconText: "󰆏"
              foreground: root.popupText
              accent: Color.accent
              leftAlign: true
              focusable: true
              enabled: root.copyAvailable
              tooltipText: "Copy track details"
              onClicked: root.copyRequested(modelData)
            }
          }

          PanelSeparator { width: parent.width; foreground: root.popupText }
          Text { text: "APPEARANCE & FEEDBACK"; color: root.mutedText; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          MediaDropdown {
            width: parent.width
            label: "Bar display"
            value: MediaController.normalizeBarDisplayMode(root.barDisplayMode)
            options: [
              { value: "full", label: "Full · artwork, title, artist" },
              { value: "title", label: "Title · artwork and title" },
              { value: "compact", label: "Compact · artwork and state" }
            ]
            foreground: root.popupText
            accent: Color.accent
            onChanged: function(value) { root.preferenceRequested("barDisplayMode", value) }
          }
          MediaToggle { width: parent.width; label: "Artwork colors"; description: "Tint accents from the current album cover."; checked: root.dynamicArtworkColor; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("dynamicArtworkColor", !root.dynamicArtworkColor) }
          MediaToggle { width: parent.width; label: "Bar progress"; description: "Show a thin playback rail under the bar pill."; checked: root.barProgressEnabled; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("barProgress", !root.barProgressEnabled) }
          MediaToggle { width: parent.width; label: "Motion"; description: "Animate artwork, metadata, pages, and progress."; checked: root.motionEnabled; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("motionEnabled", !root.motionEnabled) }
          MediaToggle { width: parent.width; label: "Track-change OSD"; description: "Show title and artist when the song changes."; checked: root.trackChangeOsd; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("trackChangeOsd", !root.trackChangeOsd) }
          MediaToggle { width: parent.width; label: "Session history"; description: "Remember up to ten tracks until the shell restarts."; checked: root.rememberSessionHistory; foreground: root.popupText; accent: Color.accent; onClicked: root.preferenceRequested("rememberSessionHistory", !root.rememberSessionHistory) }

          PanelSeparator { width: parent.width; foreground: root.popupText }
          MediaButton { width: parent.width; text: "Audio Output"; iconText: "󰕾"; foreground: root.popupText; accent: Color.accent; bordered: true; focusable: true; leftAlign: true; tooltipText: "Open Omarchy's native output picker"; onClicked: root.openAudioRequested() }
        }
      }
    }
  }
}
