# Contributing

Thanks for helping improve Omarchy Apple Music Player.

## Development setup

1. Use Omarchy 4.0.1 or newer with a working `omarchy-shell` installation.
2. Install [Bun](https://bun.sh/) for the pure and installer test suite.
3. Fork and clone the repository, then create a focused branch from `main`.
4. Run the checks before opening a pull request:

```bash
bun test
bash -n bin/omarchy-music scripts/install.sh scripts/uninstall.sh
jq empty package.json integration/omarchy-plugin/manifest.json
git diff --check
```

For live UI work, run `bash scripts/install.sh`, reload Hyprland, confirm `hyprctl configerrors` is empty, and inspect the user journal for QML warnings. Include before/after screenshots for visual changes.

## Architecture boundaries

The supported product uses Apple's official web player and Omarchy's existing MPRIS service. Contributions must not add Apple credentials, developer-token services, DOM scraping, private Apple APIs, DRM bridges, or background daemons. Never include account data, browser profiles, tokens, or private keys in a report or fixture.

Keep controls capability-aware and preserve Omarchy theme roles for readable text. Any new persistent preference must be stored inline with `bmw.media`, migrated by the installer, and covered by fixture tests.

## Pull requests

Keep each pull request narrowly scoped, explain the user-visible behavior, document limitations, and describe both automated and live verification. By contributing, you agree that your changes are licensed under the repository's MIT License.
