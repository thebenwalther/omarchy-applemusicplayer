#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$STATE_HOME/omarchy-applemusicplayer/backups/uninstall-$STAMP"
INSTALL_ROOT="$DATA_HOME/omarchy-applemusicplayer"
INSTALL_RECORD="$INSTALL_ROOT/install.json"

BINDINGS="$CONFIG_HOME/hypr/bindings.lua"
HYPRLAND="$CONFIG_HOME/hypr/hyprland.lua"
SHELL_CONFIG="$CONFIG_HOME/omarchy/shell.json"
PLUGIN_PATH="$CONFIG_HOME/omarchy/plugins/bmw.media"
SERVICE_PATH="$CONFIG_HOME/systemd/user/omarchy-applemusicplayer.service"
DESKTOP_PATH="$DATA_HOME/applications/Apple Music.desktop"
ICON_PATH="$DATA_HOME/icons/hicolor/scalable/apps/omarchy-applemusicplayer.svg"

source_repo=""
if [[ -f $INSTALL_RECORD ]] && command -v jq >/dev/null; then
  source_repo=$(jq -r '.sourceRepo // ""' "$INSTALL_RECORD" 2>/dev/null || true)
fi

mkdir -p "$BACKUP_DIR"
for file in "$BINDINGS" "$HYPRLAND" "$SHELL_CONFIG"; do
  [[ -f $file ]] && cp -a -- "$file" "$BACKUP_DIR/$(basename -- "$file")"
done

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

owned_target() {
  local target=$1
  case $target in
    "$INSTALL_ROOT"/current/*|"$INSTALL_ROOT"/releases/*) return 0 ;;
  esac
  [[ -n $source_repo ]] && case $target in
    "$source_repo"/bin/omarchy-music|"$source_repo"/scripts/uninstall.sh|"$source_repo"/assets/apple-music.svg|"$source_repo"/integration/omarchy-plugin) return 0 ;;
  esac
  return 1
}

remove_owned_link() {
  local path=$1
  [[ -L $path ]] || return 0
  local target
  target=$(readlink -- "$path")
  owned_target "$target" && rm -f -- "$path"
}

systemctl --user disable --now omarchy-applemusicplayer.service >/dev/null 2>&1 || true
rm -f -- "$SERVICE_PATH"
systemctl --user daemon-reload

remove_owned_link "$BIN_HOME/omarchy-music"
remove_owned_link "$BIN_HOME/omarchy-applemusicplayer-uninstall"
rm -f -- "$BIN_HOME/omarchy-music-mini" "$BIN_HOME/omarchy-applemusicctl"
remove_owned_link "$PLUGIN_PATH"
remove_owned_link "$ICON_PATH"
if [[ -f $DESKTOP_PATH ]] && grep -q '^X-Omarchy-AppleMusicPlayer=true$' "$DESKTOP_PATH"; then
  rm -f -- "$DESKTOP_PATH"
fi

strip_managed_block "$BINDINGS"
strip_managed_block "$HYPRLAND"

if [[ -f $SHELL_CONFIG ]] && command -v jq >/dev/null; then
  shell_temp=$(mktemp "${SHELL_CONFIG}.omarchy-applemusicplayer.XXXXXX")
  jq '
    .bar = (.bar // {})
    | .bar.layout = (.bar.layout // {})
    | .bar.layout |= with_entries(.value |= map(select(.id != "bmw.media")))
  ' "$SHELL_CONFIG" > "$shell_temp"
  chmod --reference="$SHELL_CONFIG" "$shell_temp"
  mv -- "$shell_temp" "$SHELL_CONFIG"
fi

if [[ -d $INSTALL_ROOT ]]; then rm -r -- "$INSTALL_ROOT"; fi
update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true
config_errors=$(hyprctl configerrors 2>/dev/null || true)
[[ -z $config_errors ]] || echo "$config_errors" >&2
omarchy restart shell >/dev/null 2>&1 || true

echo "Removed the Omarchy Apple Music integration."
echo "Backup: $BACKUP_DIR"
echo "Credentials and earlier backups were preserved."
