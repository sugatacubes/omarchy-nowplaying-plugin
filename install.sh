#!/usr/bin/env bash
#
# install.sh — install now-playing.waveform as a third-party Omarchy
# shell plugin. Idempotent: re-running it reinstalls cleanly.
#
# What this script does (in order):
#   1. Verifies prerequisites (jq and the Omarchy CLI).
#   2. Reads the plugin id from the local manifest.json.
#   3. Runs `omarchy plugin validate` on this directory and refuses
#      to install if the manifest is malformed.
#   4. Backs up shell.json (once) to ~/.config/omarchy/backups/<ts>/.
#   5. Copies the plugin files into ~/.config/omarchy/plugins/<id>/
#      (the bare top-level files the shell needs — QML, manifest,
#      Scripts.js, and the local widget files).
#   6. Tells the shell to rescan plugins and enables the widget in
#      the right section of the bar.
#
# What this script does NOT do:
#   - Touch /usr/share/omarchy/ (read-only by design).
#   - Modify shell.json by hand (the enable step goes through the
#     shell's IPC mutator, which preserves all existing entries).
#   - Restart the shell. Hot-reload picks up the new plugin within
#     a few hundred ms; if it doesn't, run `omarchy restart shell`.
#
# To undo: ./uninstall.sh

set -euo pipefail

# ---- 0. Locate ourselves ----
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BACKUP_ROOT="$HOME/.config/omarchy/backups/$(date -u +%Y%m%dT%H%M%SZ)"

# ---- 1. Prerequisites ----
command -v jq   >/dev/null || { echo "ERROR: jq is required (Omarchy ships it)" >&2; exit 1; }
command -v omarchy >/dev/null || { echo "ERROR: 'omarchy' command not found in PATH" >&2; exit 1; }

# ---- 2. Read the plugin id from the manifest ----
[[ -f "$REPO_DIR/manifest.json" ]] || { echo "ERROR: no manifest.json in $REPO_DIR" >&2; exit 1; }
PLUGIN_ID=$(jq -r '.id // ""' "$REPO_DIR/manifest.json")
[[ -n "$PLUGIN_ID" ]] || { echo "ERROR: manifest.json has no .id" >&2; exit 1; }
# The omarchy.* namespace is reserved for first-party plugins
[[ "$PLUGIN_ID" != omarchy.* ]] || { echo "ERROR: plugin id '$PLUGIN_ID' uses the reserved omarchy.* namespace" >&2; exit 1; }

# ---- 3. Validate the manifest ----
echo ">> validating manifest…"
omarchy plugin validate "$REPO_DIR" || { echo "ERROR: manifest validation failed" >&2; exit 1; }

# ---- 4. Back up shell.json (once per install) ----
if [[ -f "$SHELL_JSON" ]]; then
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    mkdir -p "$BACKUP_ROOT"
    cp "$SHELL_JSON" "$BACKUP_ROOT/shell.json"
    echo ">> backed up shell.json to $BACKUP_ROOT/"
  fi
fi

# ---- 5. Stage the plugin files ----
# We copy only the top-level files the shell needs. Tests, docs, README,
# LICENSE, .gitignore, etc. stay in the repo.
echo ">> installing plugin files…"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"

# If a previous version is installed, back it up before clobbering.
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  EXISTING_BACKUP="$PLUGINS_DIR/.${PLUGIN_ID}.bak.$(date -u +%Y%m%dT%H%M%S)"
  mv "$TARGET" "$EXISTING_BACKUP"
  echo ">> previous install moved to $EXISTING_BACKUP"
fi

mkdir -p "$PLUGINS_DIR"
mkdir -p "$TARGET"

# Allowlist of files/directories to copy from the repo into the plugin
# dir. Anything not in this list is left in the repo (tests, docs).
for entry in manifest.json BarWidget.qml Waveform.qml; do
  if [[ -e "$REPO_DIR/$entry" ]]; then
    cp -a "$REPO_DIR/$entry" "$TARGET/"
  fi
done

# ---- 6. Rescan the plugin directory so the shell discovers us ----
echo ">> rescanning plugins…"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# ---- 7. Wait for the plugin to appear in the catalog ----
discovered=0
for ((attempt = 0; attempt < 40; attempt++)); do
  if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null; then
    discovered=1
    break
  fi
  sleep 0.05
done
if [[ $discovered -ne 1 ]]; then
  echo "ERROR: plugin '$PLUGIN_ID' was not discovered by the shell within 2s" >&2
  echo "  Try: omarchy restart shell" >&2
  exit 1
fi

# ---- 8. Enable the widget beside Omarchy's audio control ----
DEFAULT_SECTION=$(jq -r '.barWidget.defaultSection // "right"' "$REPO_DIR/manifest.json")
echo ">> enabling '$PLUGIN_ID' in the $DEFAULT_SECTION section…"
if ! omarchy plugin enable "$PLUGIN_ID" --section "$DEFAULT_SECTION" --after omarchy.audio; then
  echo ">> omarchy.audio is not in that section; using the default position instead…"
  omarchy plugin enable "$PLUGIN_ID" --section "$DEFAULT_SECTION"
fi

# ---- 9. Done ----
cat <<DONE

Installed $PLUGIN_ID.

The widget should appear in the $DEFAULT_SECTION section of the top bar within ~1
second. If it doesn't:

  omarchy restart shell

Move it later with:

  omarchy bar move $PLUGIN_ID --section <left|center|right>

To uninstall:

  ./uninstall.sh

shell.json backup (if any): $BACKUP_ROOT/
DONE
