# Changelog

All notable changes to Omarchy Apple Music Player are documented here. Releases follow semantic versioning.

## [Unreleased]

## [3.1.0] - 2026-08-25

- Redesigned the player as a cinematic, artwork-led Omarchy popup.
- Added dynamic artwork accents, responsive layout, motion preferences, and bar progress.
- Added fading sleep timers, copy actions, session history, and optional track-change OSD.
- Preserved inline widget settings during idempotent installs and upgrades.

## [3.0.0] - 2026-08-25

- Replaced the unavailable MusicKit backend with Apple's official web player and Omarchy's MPRIS service.
- Added Apple-first source selection, capability-aware controls, and focus-or-launch behavior.
- Removed the background token service and all credential requirements.

## MusicKit prototype

The unsupported pre-v3 experiment is retained only at the `musickit-prototype-v0.1` tag.

[Unreleased]: https://github.com/thebenwalther/omarchy-applemusicplayer/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/thebenwalther/omarchy-applemusicplayer/releases/tag/v3.1.0
[3.0.0]: https://github.com/thebenwalther/omarchy-applemusicplayer/tree/v3.0.0
