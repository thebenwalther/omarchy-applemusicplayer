import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "bmw.media"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))
  readonly property string statePath: runtimeDir + "/omarchy-applemusicplayer/state.json"
  readonly property var stockMedia: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var stockPlayer: stockMedia ? stockMedia.activePlayer : null
  property var playerState: ({})

  readonly property bool hasNative: playerState && playerState.connected === true && playerState.current
  readonly property bool hasStock: stockPlayer !== null && (stockPlayer.trackTitle || stockPlayer.trackArtist)
  readonly property bool hasMedia: hasNative || hasStock
  readonly property string title: hasNative ? (playerState.current.title || "") : (hasStock ? stockPlayer.trackTitle || "" : "")
  readonly property string artist: hasNative ? (playerState.current.artist || "") : (hasStock ? stockPlayer.trackArtist || "" : "")
  readonly property string artUrl: hasNative ? (playerState.current.artwork || "") : (hasStock ? stockPlayer.trackArtUrl || "" : "")
  readonly property bool playing: hasNative ? playerState.playback === "playing" : (hasStock && stockPlayer.isPlaying)
  readonly property string playIcon: playing ? "󰏤" : "󰐊"

  property real maxLabelWidth: 210

  function parseState(raw) {
    try { playerState = JSON.parse(String(raw || "{}")) || ({}) }
    catch (error) { playerState = ({}) }
  }

  function command(name, value) {
    if (hasNative) {
      var suffix = value === undefined ? "" : " " + String(value)
      if (root.bar) root.bar.run("omarchy-applemusicctl " + name + suffix)
      return
    }
    if (!stockMedia || !stockPlayer) return
    if (name === "toggle") stockMedia.runAction("playPause", false)
    else if (name === "next") stockMedia.runAction("next", false)
    else if (name === "previous") stockMedia.runAction("previous", false)
  }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
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

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    BorderSurface {
      width: Style.space(20)
      height: Style.space(20)
      radius: Style.space(4)
      color: Style.normalFillFor(root.bar.foreground, Color.accent)
      borderSpec: Border.none()

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
        text: root.playIcon
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: labelText.implicitHeight
      clip: true
      visible: !root.bar.vertical

      Text {
        id: labelText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        property bool needsScroll: implicitWidth > parent.width

        NumberAnimation on x {
          running: labelText.needsScroll && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6500, labelText.implicitWidth * 27)
          from: parent.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-music-mini")
      } else if (mouse.button === Qt.MiddleButton) {
        root.command("next")
      } else {
        root.command("toggle")
      }
    }
    onWheel: function(wheel) {
      if (root.hasNative) {
        var current = Number(root.playerState.volume || 0)
        root.command("volume", Math.max(0, Math.min(1, current + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
      } else if (wheel.angleDelta.y > 0) root.command("previous")
      else root.command("next")
    }
    onEntered: if (root.bar) root.bar.showTooltip(root,
      root.title + (root.artist ? " — " + root.artist : "")
        + "\nLeft: play/pause · Middle: next · Right: mini player · Scroll: volume")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
