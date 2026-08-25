# Omarchy Apple Music Player

An Apple-first media experience for Omarchy built around Apple's official web player and the desktop's existing MPRIS service. No paid Apple Developer account, developer token, or stored Apple credentials are required.

![Cinematic Apple Music bar and popup](docs/widget-preview.png)

## Features

- Launches or focuses the existing [Apple Music web player](https://music.apple.com/) window
- Cinematic, responsive popup with large artwork, an artwork-derived accent, a blurred hero backdrop, and readable Omarchy-native colors
- Compact bar pill with artwork, playback state, intelligently elided metadata, and an optional progress rail
- Timeline, seeking, volume, mute, previous/next, and capability-aware playback controls
- Previous, −10 seconds, play/pause, +10 seconds, and next controls
- Apple-first source detection while keeping every MPRIS player selectable
- Capability-aware shuffle and repeat controls that only appear when supported
- Session-only sleep timer for 15, 30, or 60 minutes, or the end of the current track, with a five-second volume fade
- Copy Now Playing, optional track-change OSD, and a private in-memory history of the ten most recent unique tracks
- Persistent appearance and feedback preferences, including a motion-reduction toggle
- Keyboard navigation and existing hardware media-key support
- Update-safe user configuration with idempotent install, migration, and uninstall

## Requirements

- Omarchy with Hyprland and `omarchy-shell`
- Chromium or another browser supported by `omarchy launch ... webapp`
- `jq` and a working Widevine CDM
- An active Apple Music subscription

Bun is optional and is only used to run the development test suite.

The installed icon is local project artwork inspired by Apple Music's color palette; it is not an Apple-published trademark asset.

## Install or upgrade

```bash
git clone https://github.com/thebenwalther/omarchy-applemusicplayer.git ~/Work/github.com/thebenwalther/omarchy-applemusicplayer
cd ~/Work/github.com/thebenwalther/omarchy-applemusicplayer
bash scripts/install.sh
```

The installer:

- places `bmw.media` immediately before `omarchy.clock` in the center bar section;
- preserves existing `bmw.media` inline preferences across installs and upgrades;
- binds `SUPER + SHIFT + M` to Apple Music;
- removes the obsolete MusicKit service, mini-player binding, and control links during an upgrade;
- stores configuration and replaced-plugin backups under `$XDG_STATE_HOME/omarchy-applemusicplayer/backups` (normally `~/.local/state/...`);
- preserves the old MusicKit credential directory if it exists.

## Controls

| Surface | Action |
| --- | --- |
| `SUPER + SHIFT + M` | Launch or focus Apple Music |
| Any click on the bar widget | Open or close the detailed popup |
| Scroll on the widget | Adjust volume, or previous/next when volume is unavailable |
| `Space` in popup | Play/pause |
| `Left` / `Right` in popup | Seek −10 / +10 seconds |
| `Up` / `Down` in popup | Adjust volume by 5% |
| `Tab` / `Shift + Tab` | Move between popup controls |
| `Escape` | Close the popup |
| Hardware media keys | Previous, play/pause, and next through MPRIS |

Apple Music is selected automatically when its correlated Chromium MPRIS source is playing. Selecting another playing source manually keeps it active until it stops or disappears.

Open **More** for sleep presets, the latest five entries from session history, and widget preferences. The history keeps at most ten unique tracks in memory and is cleared when the shell restarts; entries can be copied but cannot be replayed because Apple exposes no stable track URL through MPRIS.

Sleep timers live only for the current shell session. During the final five seconds the widget fades the selected source when volume is supported, pauses it, restores its original volume while paused, and shows an Omarchy OSD. Cancelling during the fade restores the volume immediately. “End of track” is best-effort: it uses the reported position, duration, and track identity.

## Preferences

The following settings are stored inline with the `bmw.media` entry in `~/.config/omarchy/shell.json` and can be changed from **More**:

| Setting | Default | Effect |
| --- | --- | --- |
| `dynamicArtworkColor` | `true` | Uses a contrasting, vivid artwork color for accents and glow |
| `barProgress` | `true` | Shows progress along the bottom of the bar pill |
| `motionEnabled` | `true` | Enables the 220ms artwork and metadata transition |
| `trackChangeOsd` | `false` | Shows `Title — Artist` when a track changes |
| `rememberSessionHistory` | `true` | Keeps up to ten tracks until the shell restarts |

Text always uses the Omarchy popup palette; artwork colors are limited to accents, progress, borders, and glow. `wl-copy` is optional, and copy actions are disabled when it is unavailable.

## Limitations

Chromium currently exposes Apple Music playback metadata and controls but not the optional [MPRIS TrackList interface](https://specifications.freedesktop.org/mpris/latest/Track_List_Interface.html). Consequently the widget cannot show Up Next. It also cannot provide Apple-specific lyrics, favorites, or library actions without relying on private page scraping or Apple APIs.

Shuffle and repeat remain hidden when the browser does not expose those optional MPRIS properties. Offline downloads, guaranteed lossless playback, and Dolby Atmos are not provided by this integration.

The pre-cinematic web/MPRIS release is recoverable at the annotated [`v3.0.0`](../../tree/v3.0.0) tag. The earlier custom MusicKit implementation remains available at [`musickit-prototype-v0.1`](../../tree/musickit-prototype-v0.1). Reviving MusicKit requires Apple Developer Program resources and signed [developer tokens](https://developer.apple.com/documentation/applemusicapi/generating-developer-tokens).

## Development

```bash
bun test
bash -n bin/omarchy-music scripts/install.sh scripts/uninstall.sh
jq empty integration/omarchy-plugin/manifest.json package.json
```

Tests exercise source selection, PID correlation, artwork contrast and fallback, responsive thresholds, copy formatting, bounded history, every sleep-fade transition, launcher matching, clean installation, preference-preserving upgrades, idempotency, and uninstall in isolated XDG fixtures.

## Uninstall

```bash
bash scripts/uninstall.sh
```

Uninstall removes the active plugin, launcher, binding, desktop entry, and bar-layout item. It keeps credentials and all backups for manual recovery.
