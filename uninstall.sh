#!/usr/bin/env bash
#
# uninstall.sh — remove now-playing.waveform from the Omarchy shell.
# Idempotent. Run from the repo root or any directory.
#
# What this does:
#   1. Tells the shell to disable the plugin (no-op if not enabled).
#   2. Surgically removes any shell.json entries pointing at this id.
#      (Backup is taken first, once per invocation.)
#   3. Renames ~/.config/omarchy/plugins/<id>/ to .<id>.bak.<ts>
#      (so the user can recover if needed; matches omarchy-plugin-remove).
#   4. Rescans the plugin directory.
#
# This does NOT restart the shell; the inotify watcher unloads the
# widget within ~150ms.

set -euo pipefail

# ---- 0. Locate ourselves ----
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BACKUP_ROOT="$HOME/.config/omarchy/backups/$(date -u +%Y%m%dT%H%M%SZ)"

# ---- 1. Read the plugin id from the manifest ----
[[ -f "$REPO_DIR/manifest.json" ]] || { echo "ERROR: no manifest.json in $REPO_DIR (run from the plugin's repo dir)" >&2; exit 1; }
PLUGIN_ID=$(jq -r '.id // ""' "$REPO_DIR/manifest.json")
[[ -n "$PLUGIN_ID" ]] || { echo "ERROR: manifest.json has no .id" >&2; exit 1; }

# ---- 2. Back up shell.json (once per uninstall) ----
if [[ -f "$SHELL_JSON" && ! -d "$BACKUP_ROOT" ]]; then
  mkdir -p "$BACKUP_ROOT"
  cp "$SHELL_JSON" "$BACKUP_ROOT/shell.json"
  echo ">> backed up shell.json to $BACKUP_ROOT/"
fi

# ---- 3. Tell the shell to disable the plugin ----
echo ">> disabling '$PLUGIN_ID'…"
omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false >/dev/null 2>&1 || true

# ---- 4. Surgically clean shell.json ----
# Remove from all possible locations: bar.layout.{left,center,right},
# top-level plugins[], and disabledPlugins[].
if [[ -f "$SHELL_JSON" ]]; then
  echo ">> cleaning shell.json…"
  TMP="$(mktemp)"
  jq --arg id "$PLUGIN_ID" '
    del(.bar.layout.left[]   | select(.id == $id)) |
    del(.bar.layout.center[] | select(.id == $id)) |
    del(.bar.layout.right[]  | select(.id == $id)) |
    del(.plugins[]           | select(.id == $id)) |
    del(.disabledPlugins[]   | select(. == $id))
  ' "$SHELL_JSON" > "$TMP"
  mv "$TMP" "$SHELL_JSON"
fi

# ---- 5. Move the plugin dir to a backup name (not rm -rf; recoverable) ----
TARGET="$PLUGINS_DIR/$PLUGIN_ID"
BACKUP="(none; plugin was not installed)"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  BACKUP="$PLUGINS_DIR/.${PLUGIN_ID}.bak.$(date -u +%Y%m%dT%H%M%S)"
  # Find a unique backup name (the .bak. convention from omarchy-plugin-remove)
  n=1
  while [[ -e "$BACKUP" ]]; do
    BACKUP="${BACKUP%.*}-${n}"
    n=$((n + 1))
  done
  mv "$TARGET" "$BACKUP"
  echo ">> moved plugin dir to $BACKUP"
fi

# ---- 6. Rescan ----
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# ---- 7. Optional: clear the artwork cache ----
CACHE_DIR="$HOME/.cache/omarchy-now-playing"
if [[ -d "$CACHE_DIR" ]]; then
  echo ">> leaving artwork cache at $CACHE_DIR (delete manually if you want a full clean)"
fi

cat <<DONE

Uninstalled $PLUGIN_ID.

- shell.json backup: $BACKUP_ROOT/
- Plugin dir backup: $BACKUP (if moved above)
- Artwork cache:     $CACHE_DIR (still present, clear manually if wanted)

The widget should be gone from the bar within ~150ms. If it isn't:
  omarchy restart shell
DONE
