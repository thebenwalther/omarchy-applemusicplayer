#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$STATE_HOME/omarchy-applemusicplayer/backups/$STAMP"

BINDINGS="$CONFIG_HOME/hypr/bindings.lua"
HYPRLAND="$CONFIG_HOME/hypr/hyprland.lua"
SHELL_CONFIG="$CONFIG_HOME/omarchy/shell.json"
PLUGIN_ROOT="$CONFIG_HOME/omarchy/plugins"
PLUGIN_PATH="$PLUGIN_ROOT/bmw.media"
SERVICE_PATH="$CONFIG_HOME/systemd/user/omarchy-applemusicplayer.service"
DESKTOP_PATH="$DATA_HOME/applications/Apple Music.desktop"
ICON_PATH="$DATA_HOME/icons/hicolor/scalable/apps/omarchy-applemusicplayer.svg"

for command_name in jq omarchy hyprctl systemctl; do
  command -v "$command_name" >/dev/null || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

mkdir -p "$BIN_HOME" "$CONFIG_HOME/systemd/user" "$DATA_HOME/applications" \
  "$DATA_HOME/icons/hicolor/scalable/apps" "$PLUGIN_ROOT" "$BACKUP_DIR"

backup_path() {
  local path=$1
  local name=${2:-$(basename -- "$path")}
  [[ -e $path || -L $path ]] || return 0
  cp -a -- "$path" "$BACKUP_DIR/$name"
}

strip_managed_block() {
  local file=$1
  [[ -f $file ]] || return 0
  local temp
  temp=$(mktemp "${file}.omarchy-applemusicplayer.XXXXXX")
  awk '
    /omarchy-applemusicplayer:start/ { skipping=1; next }
    /omarchy-applemusicplayer:end/ { skipping=0; next }
    !skipping { print }
  ' "$file" > "$temp"
  chmod --reference="$file" "$temp"
  mv -- "$temp" "$file"
}

install_managed_block() {
  local file=$1
  local source=$2
  strip_managed_block "$file"
  printf '\n' >> "$file"
  sed -n '/omarchy-applemusicplayer:start/,/omarchy-applemusicplayer:end/p' "$source" >> "$file"
}

backup_path "$BINDINGS" bindings.lua
backup_path "$HYPRLAND" hyprland.lua
backup_path "$SHELL_CONFIG" shell.json

# Migrate backups made by older releases out of the scanned plugin directory.
shopt -s nullglob
for old_backup in "$PLUGIN_ROOT"/bmw.media.bak.omarchy-applemusicplayer-*; do
  mv -- "$old_backup" "$BACKUP_DIR/$(basename -- "$old_backup")"
done
shopt -u nullglob

if [[ -e $PLUGIN_PATH || -L $PLUGIN_PATH ]]; then
  if [[ ! -L $PLUGIN_PATH || $(readlink -- "$PLUGIN_PATH") != "$REPO/integration/omarchy-plugin" ]]; then
    backup_path "$PLUGIN_PATH" bmw.media
  fi
  if [[ -d $PLUGIN_PATH && ! -L $PLUGIN_PATH ]]; then
    rm -r -- "$PLUGIN_PATH"
  else
    rm -f -- "$PLUGIN_PATH"
  fi
fi

# Retire the MusicKit prototype runtime during upgrades without touching credentials.
systemctl --user disable --now omarchy-applemusicplayer.service >/dev/null 2>&1 || true
rm -f -- "$SERVICE_PATH"
rm -f -- "$BIN_HOME/omarchy-music-mini" "$BIN_HOME/omarchy-applemusicctl"
systemctl --user daemon-reload

ln -sfn "$REPO/bin/omarchy-music" "$BIN_HOME/omarchy-music"
ln -sfn "$REPO/assets/apple-music.svg" "$ICON_PATH"
ln -sfn "$REPO/integration/omarchy-plugin" "$PLUGIN_PATH"
sed -e "s|@REPO@|$REPO|g" "$REPO/integration/Apple Music.desktop.in" > "$DESKTOP_PATH"

install_managed_block "$BINDINGS" "$REPO/integration/hypr-bindings.lua"
strip_managed_block "$HYPRLAND"

shell_temp=$(mktemp "${SHELL_CONFIG}.omarchy-applemusicplayer.XXXXXX")
jq '
  .bar = (.bar // {})
  | .bar.layout = (.bar.layout // {})
  | .bar.layout |= with_entries(.value |= map(select(.id != "bmw.media")))
  | .bar.layout.center = (
      (.bar.layout.center // []) as $center
      | ($center | map(.id) | index("omarchy.clock")) as $clock
      | if $clock == null
        then $center + [{"id":"bmw.media"}]
        else $center[0:$clock] + [{"id":"bmw.media"}] + $center[$clock:]
        end
    )
' "$SHELL_CONFIG" > "$shell_temp"
chmod --reference="$SHELL_CONFIG" "$shell_temp"
mv -- "$shell_temp" "$SHELL_CONFIG"

chmod 0755 "$REPO/bin/omarchy-music" "$REPO/scripts/install.sh" "$REPO/scripts/uninstall.sh"
chmod 0644 "$DESKTOP_PATH"
update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true

hyprctl reload >/dev/null
config_errors=$(hyprctl configerrors || true)
if [[ -n $config_errors ]]; then
  echo "$config_errors" >&2
  exit 1
fi
omarchy restart shell

echo "Installed Omarchy Apple Music integration from $REPO"
echo "Backup: $BACKUP_DIR"
echo "Open Apple Music with SUPER + SHIFT + M."
