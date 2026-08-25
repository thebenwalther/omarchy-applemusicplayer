#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUN=$(command -v bun)
STAMP=$(date +%Y%m%d-%H%M%S)
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_HOME="$HOME/.local/bin"

mkdir -p "$BIN_HOME" "$CONFIG_HOME/systemd/user" "$DATA_HOME/applications" "$DATA_HOME/icons/hicolor/scalable/apps" "$CONFIG_HOME/omarchy/plugins"

for file in "$CONFIG_HOME/hypr/bindings.lua" "$CONFIG_HOME/hypr/hyprland.lua" "$CONFIG_HOME/omarchy/shell.json"; do
  [[ -f $file ]] && cp -a "$file" "$file.bak.omarchy-applemusicplayer-$STAMP"
done

ln -sfn "$REPO/bin/omarchy-music" "$BIN_HOME/omarchy-music"
ln -sfn "$REPO/bin/omarchy-music-mini" "$BIN_HOME/omarchy-music-mini"
ln -sfn "$REPO/bin/omarchy-applemusicctl" "$BIN_HOME/omarchy-applemusicctl"
ln -sfn "$REPO/web/icon.svg" "$DATA_HOME/icons/hicolor/scalable/apps/omarchy-applemusicplayer.svg"

sed -e "s|@REPO@|$REPO|g" -e "s|@BUN@|$BUN|g" \
  "$REPO/integration/systemd/omarchy-applemusicplayer.service.in" \
  > "$CONFIG_HOME/systemd/user/omarchy-applemusicplayer.service"
sed -e "s|@REPO@|$REPO|g" "$REPO/integration/Apple Music.desktop.in" \
  > "$DATA_HOME/applications/Apple Music.desktop"

PLUGIN_PATH="$CONFIG_HOME/omarchy/plugins/bmw.media"
if [[ -e $PLUGIN_PATH && ! -L $PLUGIN_PATH ]]; then
  mv "$PLUGIN_PATH" "$PLUGIN_PATH.bak.omarchy-applemusicplayer-$STAMP"
fi
ln -sfn "$REPO/integration/omarchy-plugin" "$PLUGIN_PATH"

if ! grep -q 'omarchy-applemusicplayer:start' "$CONFIG_HOME/hypr/bindings.lua"; then
  printf '\n' >> "$CONFIG_HOME/hypr/bindings.lua"
  sed -n '/omarchy-applemusicplayer:start/,/omarchy-applemusicplayer:end/p' "$REPO/integration/hypr-bindings.lua" >> "$CONFIG_HOME/hypr/bindings.lua"
fi
if ! grep -q 'omarchy-applemusicplayer:start' "$CONFIG_HOME/hypr/hyprland.lua"; then
  printf '\n' >> "$CONFIG_HOME/hypr/hyprland.lua"
  sed -n '/omarchy-applemusicplayer:start/,/omarchy-applemusicplayer:end/p' "$REPO/integration/hypr-windows.lua" >> "$CONFIG_HOME/hypr/hyprland.lua"
fi

REPO="$REPO" bun -e '
  import { readFileSync, writeFileSync } from "node:fs";
  const path = `${process.env.HOME}/.config/omarchy/shell.json`;
  const config = JSON.parse(readFileSync(path, "utf8"));
  const sections = config.bar?.layout || {};
  for (const name of Object.keys(sections)) sections[name] = sections[name].filter(item => item.id !== "bmw.media");
  const center = sections.center ||= [];
  const clock = center.findIndex(item => item.id === "omarchy.clock");
  center.splice(clock < 0 ? center.length : clock, 0, { id: "bmw.media" });
  writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`);
'

chmod 0755 "$REPO/bin/omarchy-music" "$REPO/bin/omarchy-music-mini" "$REPO/bin/omarchy-applemusicctl"
chmod 0644 "$CONFIG_HOME/systemd/user/omarchy-applemusicplayer.service" "$DATA_HOME/applications/Apple Music.desktop"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-applemusicplayer.service
update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
hyprctl reload
omarchy-shell shell rescanPlugins || omarchy restart shell

echo "Installed Omarchy Apple Music Player from $REPO"
echo "Open it with SUPER + SHIFT + M and configure MusicKit in the setup dialog."
