// Shared helper functions for the now-playing plugin.
// All inputs are defensive (null/undefined/empty-string tolerant) so callers
// don't need to guard at every call site.

// Browser desktopEntry values that indicate the player is a browser
// streaming media from a website. Anything matching this set gets formatted
// as "<title or site> — <Browser>".
var BROWSER_ENTRIES = {
  "firefox": "Firefox",
  "firefox-developer-edition": "Firefox",
  "chromium": "Chromium",
  "chromium-browser": "Chromium",
  "chrome": "Chrome",
  "google-chrome": "Chrome",
  "google-chrome-stable": "Chrome",
  "brave-browser": "Brave",
  "zen": "Zen"
}

// Friendly site labels for known streaming domains. Matched against the
// page title or track title; falls back to raw title if no rule matches.
var SITE_LABELS = [
  { match: /music\.youtube\.com/i,      label: "YouTube Music" },
  { match: /youtube\.com|\(youtube\)|\[youtube\]/i, label: "YouTube" },
  { match: /netflix\.com/i,             label: "Netflix" },
  { match: /soundcloud\.com/i,          label: "SoundCloud" },
  { match: /bandcamp\.com/i,            label: "Bandcamp" },
  { match: /open\.spotify\.com/i,       label: "Spotify Web" },
  { match: /twitch\.tv/i,               label: "Twitch" },
  { match: /vimeo\.com/i,               label: "Vimeo" }
]

// Strip the leading "Artist - " (or "Artist — ") prefix that many music
// players include in the track title, so we can show the page title alone
// in the "site — browser" format. This is a heuristic; a real artist tag
// (e.g. "Lana Del Rey - Video Games") gets correctly split, and a song
// whose title itself contains a hyphen ("Mr. Brightside - The Killers")
// stays intact.
function stripLeadingArtist(title, artist) {
  var t = String(title || "")
  if (!t || !artist) return t
  var a = String(artist)
  // Try with " - ", " — ", and " – " separators
  var seps = [" - ", " — ", " – "]
  for (var i = 0; i < seps.length; i++) {
    var idx = t.indexOf(seps[i])
    if (idx > 0 && t.substring(0, idx).toLowerCase() === a.toLowerCase()) {
      return t.substring(idx + seps[i].length)
    }
  }
  return t
}

// Return a clean page/site title for browser-streamed media. Strips a
// leading "Artist - " prefix, then matches against the SITE_LABELS list
// to map generic page titles to friendlier labels.
function siteLabelFor(rawTitle) {
  var t = String(rawTitle || "").trim()
  if (!t) return ""
  for (var i = 0; i < SITE_LABELS.length; i++) {
    if (SITE_LABELS[i].match.test(t)) return SITE_LABELS[i].label
  }
  // Truncate very long page titles for the bar/panel display
  if (t.length > 60) return t.substring(0, 57) + "..."
  return t
}

// Format a player object as a human-readable source label.
// - For native apps (Spotify, VLC, mpv): returns Identity as-is.
// - For browsers: returns "<Site> — <Browser>" or "<Page Title> — <Browser>".
// - For playerctld proxies: returns the proxied player's label.
function formatPlayerSource(player) {
  if (!player) return ""
  try {
    var desktop = String(player.desktopEntry || "").toLowerCase()
    var identity = String(player.identity || "")
    var dbus = String(player.dbusName || "")
    var isProxy = dbus.toLowerCase().indexOf("playerctld") !== -1
                 || desktop === "playerctld"

    // Playerctld proxies inherit from another real player; try to be honest
    // about the underlying app.
    if (isProxy) {
      // The proxied player info is in MprisPlayer.children or via trackTitle;
      // best-effort: if there's a real desktopEntry, use it.
      if (identity && identity.toLowerCase() !== "playerctl")
        return identity
      if (desktop && desktop !== "playerctld") return desktop
      // fall through to browser branch
    }

    // Native apps: use Identity directly. The player already gives us
    // "Spotify", "VLC media player", etc. — no need to decorate.
    if (BROWSER_ENTRIES[desktop] === undefined) {
      return identity || desktop || "Media"
    }

    // Browser: build "<Site> — <Browser>"
    var browserName = BROWSER_ENTRIES[desktop]
    var pageTitle = stripLeadingArtist(player.trackTitle, player.trackArtist)
    var site = siteLabelFor(pageTitle) || siteLabelFor(player.trackTitle) || "Web"
    return site + " — " + browserName
  } catch (e) {
    return "Media"
  }
}

// Format a duration in microseconds as "M:SS" or "H:MM:SS" if over an hour.
function formatDuration(us) {
  var n = Number(us)
  if (!isFinite(n) || n <= 0) return ""
  var totalSeconds = Math.floor(n / 1000000)
  var hours = Math.floor(totalSeconds / 3600)
  var minutes = Math.floor((totalSeconds % 3600) / 60)
  var seconds = totalSeconds % 60
  var pad = function(v) { return v < 10 ? "0" + v : "" + v }
  if (hours > 0) return hours + ":" + pad(minutes) + ":" + pad(seconds)
  return minutes + ":" + pad(seconds)
}

// Best-effort SHA-1-ish hash of a string for cache filenames. We don't need
// cryptographic strength; we just need a stable, filesystem-safe identifier.
// Returns 32 hex chars.
function hashKey(s) {
  var str = String(s || "")
  // djb2 + sdbm combined — fast and good enough for cache keys
  var h1 = 5381, h2 = 0
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i)
    h1 = ((h1 << 5) + h1 + c) | 0   // h1 * 33 + c
    h2 = (h2 * 65599 + c) | 0
  }
  // Convert to unsigned 32-bit hex, padded
  function toHex(n) {
    var v = n < 0 ? n + 0x100000000 : n
    var s = v.toString(16)
    while (s.length < 8) s = "0" + s
    return s
  }
  return toHex(h1) + toHex(h2)
}

// Map an HTTP Content-Type to a file extension for the cached artwork.
function extensionForContentType(ct) {
  var t = String(ct || "").toLowerCase()
  if (t.indexOf("jpeg") !== -1 || t.indexOf("jpg") !== -1) return "jpg"
  if (t.indexOf("png") !== -1) return "png"
  if (t.indexOf("webp") !== -1) return "webp"
  if (t.indexOf("avif") !== -1) return "avif"
  if (t.indexOf("gif") !== -1) return "gif"
  return "img"  // unknown; Image{} will try to decode it
}

// Pure module exports for testing from Node (mirrored in tests/test_helpers.py).
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    formatPlayerSource: formatPlayerSource,
    siteLabelFor: siteLabelFor,
    stripLeadingArtist: stripLeadingArtist,
    formatDuration: formatDuration,
    hashKey: hashKey,
    extensionForContentType: extensionForContentType,
    BROWSER_ENTRIES: BROWSER_ENTRIES
  }
}
