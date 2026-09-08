import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import "Scripts.js" as Scripts

// Reactive media model for the now-playing widget. Wraps Quickshell's
// native Mpris binding and exposes a normalized snapshot of the active
// player that the bar widget and popup panel can both consume.
//
// Active-player selection reuses Omarchy's first-party omarchy.media
// service when present (it has the most refined selection logic — pipewire
// stream correlation, proxy handling, preferred-player memory, etc.). We
// only fall back to our own selection if the service isn't running.
Item {
  id: root

  // ----- The omarchy.media service (if loaded) -----
  // `bar` is the Bar instance injected by the host; it carries the shell,
  // which exposes `firstPartyServiceFor("omarchy.media")` to find Omarchy's
  // built-in media service (loaded by default via its keepLoaded: true
  // manifest flag). This is the same access pattern Omarchy's own
  // omarchy.media BarWidget uses.
  readonly property var mediaService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var _servicePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool _hasService: mediaService !== null && mediaService !== undefined

  // ----- The active player (reactive) -----
  // Prefer the service's selection; fall back to picking the first playing
  // player from Mpris.players ourselves. The service's algorithm already
  // handles browser players, proxies, and PipeWire stream correlation.
  readonly property var activePlayer: _hasService
    ? _servicePlayer
    : selectOwnActivePlayer()

  // ----- Reactive media snapshot (everything the UI needs) -----
  readonly property bool hasMedia: activePlayer !== null
    && (activePlayer.trackTitle || activePlayer.trackArtist || activePlayer.identity)
  readonly property bool isPlaying: !!(activePlayer && activePlayer.isPlaying)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artworkUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string playerSource: Scripts.formatPlayerSource(activePlayer)
  readonly property string playerIdentity: activePlayer ? (activePlayer.identity || "") : ""
  readonly property string playerDesktopEntry: activePlayer ? (activePlayer.desktopEntry || "") : ""

  // ----- Optional: surface-level page title (stripped of "Artist - " prefix) -----
  readonly property string pageTitle: {
    if (!activePlayer) return ""
    return Scripts.stripLeadingArtist(activePlayer.trackTitle, activePlayer.trackArtist)
  }

  // ----- Capabilities (for greying out prev/next buttons) -----
  readonly property bool canPlay: !!(activePlayer && (activePlayer.canPlay || activePlayer.canTogglePlaying))
  readonly property bool canPause: !!(activePlayer && (activePlayer.canPause || activePlayer.canTogglePlaying))
  readonly property bool canNext: !!(activePlayer && activePlayer.canGoNext)
  readonly property bool canPrev: !!(activePlayer && activePlayer.canGoPrevious)
  readonly property bool canControl: !!(activePlayer && (
    activePlayer.canPlay || activePlayer.canPause || activePlayer.canTogglePlaying ||
    activePlayer.canGoNext || activePlayer.canGoPrevious
  ))

  // ----- Control actions -----
  function togglePlayPause() {
    if (!activePlayer) return
    try {
      // Prefer the most-specific action available so OSD feedback (via
      // omarchy.media service) can show the right label. Fall back to
      // togglePlaying which always works.
      if (activePlayer.isPlaying && activePlayer.canPause) activePlayer.pause()
      else if (!activePlayer.isPlaying && activePlayer.canPlay) activePlayer.play()
      else if (activePlayer.canTogglePlaying) activePlayer.togglePlaying()
    } catch (e) { /* swallow — player may have died */ }
  }
  function next() {
    if (!activePlayer) return
    try { if (activePlayer.canGoNext) activePlayer.next() } catch (e) {}
  }
  function previous() {
    if (!activePlayer) return
    try { if (activePlayer.canGoPrevious) activePlayer.previous() } catch (e) {}
  }

  // ----- Fallback active-player selection (only used if the service is
  // absent). Mirrors the spirit of Omarchy's algorithm: prefer playing,
  // then paused, then any; within a status tier, prefer non-proxy players
  // (real app > playerctld proxy), then most-recently-active. -----
  property var _lastPlayerActivity: ({})  // dbusName -> Date.now() ms

  readonly property var _allPlayers: Mpris.players ? Mpris.players.values : []
  // Re-evaluate selection whenever the player set changes
  on_AllPlayersChanged: _refreshActivityMap()
  Component.onCompleted: _refreshActivityMap()

  function _refreshActivityMap() {
    var players = root._allPlayers
    var next = root._lastPlayerActivity
    var now = Date.now()
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      var key = String(p.dbusName || p.identity || p.desktopEntry || "")
      if (key && next[key] === undefined) next[key] = now
    }
    for (var k in next) {
      var stillThere = false
      for (var j = 0; j < players.length; j++) {
        var pj = players[j]
        if (!pj) continue
        var kj = String(pj.dbusName || pj.identity || pj.desktopEntry || "")
        if (kj === k) { stillThere = true; break }
      }
      if (!stillThere) delete next[k]
    }
    root._lastPlayerActivity = next
  }

  function selectOwnActivePlayer() {
    var players = root._allPlayers
    if (!players || players.length === 0) return null

    var sorted = players.slice()
    var statusWeight = function(p) {
      if (p.isPlaying) return 2
      if (p.playbackState === "Paused") return 1
      return 0
    }
    var proxyWeight = function(p) {
      var dbus = String(p.dbusName || "").toLowerCase()
      var desk = String(p.desktopEntry || "").toLowerCase()
      return (dbus.indexOf("playerctld") !== -1 || desk === "playerctld") ? 1 : 0
    }
    var nextActivity = root._lastPlayerActivity
    sorted.sort(function(a, b) {
      var sa = statusWeight(a), sb = statusWeight(b)
      if (sa !== sb) return sb - sa
      var pa = proxyWeight(a), pb = proxyWeight(b)
      if (pa !== pb) return pa - pb
      var ka = String(a.dbusName || a.identity || "")
      var kb = String(b.dbusName || b.identity || "")
      var ta = nextActivity[ka] || 0, tb = nextActivity[kb] || 0
      return tb - ta
    })
    return sorted[0] || null
  }
}
