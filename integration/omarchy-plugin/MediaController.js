function asArray(value) {
  return Array.isArray(value) ? value : []
}

function playerKey(player) {
  if (!player) return ""
  return String(player.dbusName || player.desktopEntry || player.identity || "")
}

function dbusInstancePid(dbusName) {
  var match = String(dbusName || "").match(/\.instance([0-9]+)$/)
  return match ? Number(match[1]) : 0
}

function appleMusicPids(rawClients) {
  var clients = rawClients
  if (typeof rawClients === "string") {
    try { clients = JSON.parse(rawClients) }
    catch (_) { return [] }
  }

  var result = []
  var seen = {}
  var list = asArray(clients)
  for (var i = 0; i < list.length; i++) {
    var client = list[i] || {}
    var haystack = String(client.class || "") + " " + String(client.initialClass || "")
    if (haystack.toLowerCase().indexOf("music.apple.com") === -1) continue
    var pid = Number(client.pid || 0)
    if (pid > 0 && !seen[pid]) {
      result.push(pid)
      seen[pid] = true
    }
  }
  return result
}

function isApplePlayer(player, pids) {
  var pid = dbusInstancePid(player && player.dbusName)
  return pid > 0 && asArray(pids).indexOf(pid) !== -1
}

function applePlayerKey(players, pids) {
  var list = asArray(players)
  for (var i = 0; i < list.length; i++) {
    if (isApplePlayer(list[i], pids)) return playerKey(list[i])
  }
  return ""
}

function findPlayer(players, key) {
  var list = asArray(players)
  for (var i = 0; i < list.length; i++) {
    if (playerKey(list[i]) === String(key || "")) return list[i]
  }
  return null
}

function choosePlayerKey(players, pids, manualKey, fallbackKey) {
  var manual = findPlayer(players, manualKey)
  if (manual && manual.isPlaying) return playerKey(manual)

  var appleKey = applePlayerKey(players, pids)
  var apple = findPlayer(players, appleKey)
  if (apple && apple.isPlaying) return appleKey

  var fallback = findPlayer(players, fallbackKey)
  if (fallback) return playerKey(fallback)
  if (apple) return appleKey
  return asArray(players).length > 0 ? playerKey(players[0]) : ""
}

function sourceName(player, appleKey) {
  if (!player) return "Media"
  if (playerKey(player) === String(appleKey || "")) return "Apple Music"
  return String(player.identity || player.desktopEntry || "Media")
}

function sourceDetail(player) {
  if (!player) return "Idle"
  var title = String(player.trackTitle || "")
  var artist = String(player.trackArtist || "")
  if (title && artist) return title + " — " + artist
  return title || artist || "Idle"
}

function capabilities(player) {
  return {
    shuffle: !!(player && player.shuffleSupported),
    loop: !!(player && player.loopSupported)
  }
}

function trackSignature(player) {
  if (!player) return ""
  return [player.trackTitle || "", player.trackArtist || "", player.trackAlbum || "", player.trackArtUrl || ""].join("\u001f")
}

function formatTime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var remainder = total % 60
  if (hours > 0) return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (remainder < 10 ? "0" : "") + remainder
  return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
}

function timerDeadline(minutes, nowMs) {
  return Number(nowMs || Date.now()) + Math.max(0, Number(minutes) || 0) * 60000
}

function timerRemaining(deadlineMs, nowMs) {
  var remaining = Math.max(0, Math.ceil((Number(deadlineMs) - Number(nowMs || Date.now())) / 1000))
  return formatTime(remaining)
}

function endOfTrackReached(player, originalSignature, thresholdSeconds) {
  if (!player) return true
  if (trackSignature(player) !== String(originalSignature || "")) return true
  var duration = Number(player.length || 0)
  var position = Number(player.position || 0)
  if (duration <= 0) return false
  return position >= Math.max(0, duration - Math.max(0.5, Number(thresholdSeconds) || 1.5))
}

if (typeof module !== "undefined") {
  module.exports = {
    playerKey: playerKey,
    dbusInstancePid: dbusInstancePid,
    appleMusicPids: appleMusicPids,
    isApplePlayer: isApplePlayer,
    applePlayerKey: applePlayerKey,
    findPlayer: findPlayer,
    choosePlayerKey: choosePlayerKey,
    sourceName: sourceName,
    sourceDetail: sourceDetail,
    capabilities: capabilities,
    trackSignature: trackSignature,
    formatTime: formatTime,
    timerDeadline: timerDeadline,
    timerRemaining: timerRemaining,
    endOfTrackReached: endOfTrackReached
  }
}
