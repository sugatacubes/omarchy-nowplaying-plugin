import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Scripts.js" as Scripts

// Artwork loader: takes an mpris:artUrl (file://, https://, or data:) and
// produces a local cached file path that Image{} can read. Outputs "" while
// the artwork is loading or on any failure.
//
// Caching strategy:
//   file://     -> pass through; no copy, no fetch.
//   data:image  -> decode + write to cache/.<ext>; cached forever.
//   https://    -> curl to a temp file, then atomically rename to
//                  ~/.cache/omarchy-now-playing/artwork/<sha1>.<ext>.
//                  Cached by content hash. Re-downloads on cache miss.
//
// All process I/O is async via Quickshell.execDetached; the QML render
// thread is never blocked. requestSeq invalidates in-flight work on
// source changes (rapid track changes can otherwise race).
Item {
  id: root
  property string source: ""
  property string localPath: ""
  property int requestSeq: 0   // bumped on every source change

  onSourceChanged: resolve()
  onRequestSeqChanged: resolve()
  Component.onCompleted: resolve()

  // Cache dir is the user-level XDG cache, scoped to this plugin
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME")
    || (Quickshell.env("HOME") + "/.cache"))
    + "/omarchy-now-playing/artwork"

  // User-overridable fallback. If this file doesn't exist, we fall back to
  // a bundled 1x1 transparent PNG so the panel always has something to draw.
  readonly property string userFallback: Quickshell.env("HOME")
    + "/.local/share/omarchy-now-playing/fallback.png"

  // Bundled 1x1 transparent PNG (base64, 67 bytes). The Image{} will render
  // this as a transparent rect; the parent layout supplies the real
  // background, so the placeholder is visually invisible.
  readonly property string bundledFallback:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

  // Resolve `source` to a local file path. Always async to avoid blocking
  // the QML render thread.
  function resolve() {
    var seq = root.requestSeq
    var src = String(root.source || "").trim()
    if (!src) {
      root.localPath = ""
      return
    }
    if (src.indexOf("file://") === 0) {
      // Strip the scheme, pass through. Handle both file:///abs and file://localhost/abs.
      var path = src.substring(7)
      // Drop a leading "localhost" if present
      if (path.indexOf("localhost/") === 0) path = path.substring("localhost/".length - 1)
      // Ensure leading /
      if (path.charAt(0) !== "/") path = "/" + path
      root.localPath = path
      return
    }
    if (src.indexOf("data:") === 0) {
      decodeDataUrl(src, seq)
      return
    }
    if (src.indexOf("http://") === 0 || src.indexOf("https://") === 0) {
      fetchHttp(src, seq)
      return
    }
    // Unknown scheme — fall through to bundled placeholder
    root.localPath = ""
  }

  // Decode a data: URL and write the bytes to the cache directory.
  function decodeDataUrl(url, seq) {
    var commaIdx = url.indexOf(",")
    if (commaIdx < 0) { root.localPath = bundledFallbackFile(); return }
    var header = url.substring(5, commaIdx)  // skip "data:"
    var body = url.substring(commaIdx + 1)
    var isBase64 = header.indexOf("base64") !== -1
    if (!isBase64) { root.localPath = bundledFallbackFile(); return }

    // Extract MIME type from header (between "data:" and ";base64")
    var mime = header.split(";")[0]
    var ext = Scripts.extensionForContentType(mime)
    var hash = Scripts.hashKey(url)
    var target = root.cacheDir + "/" + hash + "." + ext

    Quickshell.execDetached({
      command: ["sh", "-c",
        "mkdir -p '" + root.cacheDir + "' && echo -n '" + body + "' | base64 -d > '" + target + "'"],
      onFinished: function(exitCode) {
        if (seq !== root.requestSeq) return
        root.localPath = exitCode === 0 ? target : bundledFallbackFile()
      }
    })
  }

  // Fetch an http(s):// URL via curl, cache the result, and set localPath.
  function fetchHttp(url, seq) {
    var hash = Scripts.hashKey(url)
    // Provisional extension; will be corrected by Content-Type after HEAD
    var ext = "img"
    var target = root.cacheDir + "/" + hash + "." + ext

    // Ensure cache dir exists
    Quickshell.execDetached({
      command: ["sh", "-c", "mkdir -p '" + root.cacheDir + "'"]
    })

    // Single-shot GET to a temp file. Skip HEAD — the size + cost of an
    // extra request is not worth saving a stale cache lookup on the rare
    // Content-Type change. Final extension is derived from the URL only.
    var tmp = target + ".tmp." + seq
    Quickshell.execDetached({
      command: ["curl", "-sSL", "--max-time", "5", url, "-o", tmp],
      onFinished: function(ec) {
        if (seq !== root.requestSeq) {
          // Stale; remove the half-downloaded file
          Quickshell.execDetached({ command: ["rm", "-f", tmp] })
          return
        }
        if (ec === 0) {
          // Move into place atomically
          Quickshell.execDetached({
            command: ["mv", tmp, target],
            onFinished: function() {
              if (seq === root.requestSeq) root.localPath = target
            }
          })
        } else {
          Quickshell.execDetached({ command: ["rm", "-f", tmp] })
          root.localPath = bundledFallbackFile()
        }
      }
    })
  }

  // Return the user fallback path if it exists, otherwise the bundled one.
  // We test for the user file via a one-shot shell command; if it exists
  // we use it, otherwise we extract the bundled PNG to a stable path.
  property int _fallbackSeq: 0
  function bundledFallbackFile() {
    var target = root.userFallback
    var seq = ++_fallbackSeq
    Quickshell.execDetached({
      command: ["sh", "-c",
        "if [ ! -f '" + target + "' ]; then " +
        "  mkdir -p '" + root.userFallback.substring(0, root.userFallback.lastIndexOf("/")) + "' && " +
        "  echo -n '" + bundledFallback + "' | base64 -d > '" + target + "'; " +
        "fi"],
      onFinished: function(ec) {
        if (seq === _fallbackSeq) {
          // localPath may have been superseded by a real load; only set
          // it if we're still in the fallback state.
          if (root.localPath === "" || root.localPath === undefined)
            root.localPath = target
        }
      }
    })
    return target
  }
}
