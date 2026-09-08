# Media Halo for Omarchy

Media Halo is a compact, theme-aware now-playing widget for the Omarchy top
bar. Its circular waveform animates while media is playing and settles into a
quiet ring when paused.

It uses Omarchy's native `omarchy.media` service, so player selection stays in
sync with active PipeWire streams and MPRIS players. There is no `playerctl`,
polling loop, or extra background process.

## Controls

| Gesture | Action |
| --- | --- |
| Left click | Play / pause |
| Right click | Open now-playing popup |
| Middle click | Next track |
| Scroll up / down | Previous / next |

The popup shows cover art, title, artist, album, playback state, transport
controls, and a source chooser when more than one media player is available.

## Previews

<img width="537" height="242" alt="image" src="https://github.com/user-attachments/assets/8bd6f5e2-1af7-4ef9-a437-610f51c7b1ee" />


## Install

```bash
./install.sh
```

The installer validates the manifest, backs up `shell.json`, installs only the
runtime files under `~/.config/omarchy/plugins/now-playing.waveform/`, rescans
the shell, and places the widget after `omarchy.audio` on the right side.

If the shell is not currently running, start it and run the installer again, or
run `omarchy restart shell` followed by:

```bash
omarchy plugin enable now-playing.waveform --section right --after omarchy.audio
```

## Settings

Settings are inline in the widget's entry in
`~/.config/omarchy/shell.json`:

```json
{
  "id": "now-playing.waveform",
  "showTitle": false,
  "maxLabelWidth": 180,
  "ringBars": 12
}
```

- `showTitle` adds a scrolling title beside the circular control.
- `maxLabelWidth` caps that title's width.
- `ringBars` accepts 8–24 radial bars.

## Uninstall

```bash
./uninstall.sh
```

Uninstalling is recoverable: both the shell config and installed plugin folder
are moved to timestamped backups.

## Compatibility note

Playback control requires an MPRIS-capable player. This covers common desktop
players and browser media sessions, including background video in browsers that
publish MPRIS. Apps that only output raw PipeWire audio can be detected as audio
streams, but Linux has no universal play/pause command for them.
