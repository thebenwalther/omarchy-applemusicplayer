# Omarchy Apple Music Player

An Omarchy-native Apple Music desktop player powered by MusicKit on the Web. Chromium remains the protected-media engine; this project supplies the focused player UI, owned Up Next queue, mini player, bar state, and Hyprland integration.

## Features

- Apple Music catalog search, recommendations, history, and library views
- Album, playlist, and song playback through Apple's MusicKit JavaScript SDK
- Editable Up Next queue with current track, artwork, progress, volume, shuffle, and repeat
- Chromium Media Session metadata for MPRIS and hardware media keys
- Omarchy bar controls and a dedicated special-workspace mini player
- Live colors from the active Omarchy theme
- Loopback-only Bun service with short-lived, origin-bound developer tokens

## Requirements

- Omarchy with Hyprland and `omarchy-shell`
- Bun, Chromium, `jq`, `curl`, and a working Widevine CDM
- Active Apple Music subscription
- Apple Developer Program membership
- A MusicKit Media ID and associated private key

Apple's setup documentation:

- [MusicKit on the Web](https://developer.apple.com/musickit/web/)
- [Create a media identifier and private key](https://developer.apple.com/help/account/configure-app-capabilities/create-a-media-identifier-and-private-key/)
- [Generate developer tokens](https://developer.apple.com/documentation/applemusicapi/generating-developer-tokens)

## Install

```bash
git clone https://github.com/thebenwalther/omarchy-applemusicplayer.git ~/Work/github.com/thebenwalther/omarchy-applemusicplayer
cd ~/Work/github.com/thebenwalther/omarchy-applemusicplayer
bun test
bun run install:user
```

The installer backs up the existing Hyprland bindings, Hyprland root config, Omarchy shell configuration, and `bmw.media` plugin before installing user-owned integration.

Open the player with `SUPER + SHIFT + M`. On first launch, enter the Team ID, Key ID, optional Media ID, and contents of the `.p8` key in the setup dialog. The key is written to:

```text
~/.config/omarchy-applemusicplayer/config.json
```

The file and its parent directory are restricted to the current user. Apple account authorization then happens inside MusicKit; this project does not request or store the Apple password or two-factor code.

## Controls

| Surface | Action |
| --- | --- |
| `SUPER + SHIFT + M` | Launch or focus the full player |
| `SUPER + ALT + M` | Toggle the mini player special workspace |
| Bar left click | Play/pause |
| Bar middle click | Next track |
| Bar right click | Toggle mini player |
| Bar scroll | Volume |
| Hardware media keys | Previous, play/pause, and next through MPRIS |

## Development

```bash
bun run dev
```

The service listens only on IPv4 loopback. The full player uses `http://applemusic.localhost:17689/`; the mini route uses a separate `.localhost` hostname so Hyprland can identify its Chromium app window reliably. `/mini` is a control-only client, so a second MusicKit playback instance is never created.

Runtime player state is written atomically to:

```text
$XDG_RUNTIME_DIR/omarchy-applemusicplayer/state.json
```

The bar watches that file directly. Commands pass through `omarchy-applemusicctl` to the loopback service and are delivered to the player over a server-sent event stream.

### Commands

```bash
omarchy-applemusicctl toggle
omarchy-applemusicctl previous
omarchy-applemusicctl next
omarchy-applemusicctl volume 0.7
omarchy-applemusicctl seek 90
```

## Security model

- The service binds to IPv4 loopback only.
- Browser mutations require the exact same origin.
- Native control calls require a non-simple custom header and remain loopback-only.
- The `.p8` key never enters frontend JavaScript except during the local setup submission; it is used only by the Bun service to sign a 12-hour developer token.
- The developer token is restricted to the player's fixed localhost origin.
- MusicKit manages the Music User Token in the Chromium player profile.

## Limitations

- The main player window must remain open while music is playing.
- Queue reorder/remove may briefly rebuild the MusicKit queue when the SDK does not expose a direct mutation for an item.
- Offline downloads, synchronized lyrics, music videos, lossless, and Dolby Atmos are outside v1.
- Apple may change MusicKit JS behavior independently of this project.

## Uninstall

```bash
bun run uninstall:user
```

The uninstall script leaves the credential file and timestamped configuration backups in place. Restore the desired backups manually, then remove `~/.config/omarchy-applemusicplayer` only if the signing key should also be deleted.
