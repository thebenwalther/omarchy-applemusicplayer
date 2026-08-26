#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
MODE=copy
case ${1:-} in
  "") ;;
  --link) MODE=link ;;
  --help|-h)
    echo "Usage: bash scripts/install.sh [--link]"
    echo "  --link  use the source checkout for development hot reload"
    exit 0
    ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Only one option is supported." >&2; exit 2; }

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$STATE_HOME/omarchy-applemusicplayer/backups/$STAMP"
INSTALL_ROOT="$DATA_HOME/omarchy-applemusicplayer"
RELEASES_ROOT="$INSTALL_ROOT/releases"
CURRENT_LINK="$INSTALL_ROOT/current"
INSTALL_RECORD="$INSTALL_ROOT/install.json"
VERSION=$(tr -d '[:space:]' < "$REPO/VERSION")

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

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION: $VERSION" >&2; exit 1; }
[[ $(jq -r .version "$REPO/package.json") == "$VERSION" ]] || { echo "package.json version does not match VERSION" >&2; exit 1; }
[[ $(jq -r .version "$REPO/integration/omarchy-plugin/manifest.json") == "$VERSION" ]] || { echo "plugin manifest version does not match VERSION" >&2; exit 1; }

mkdir -p "$BIN_HOME" "$CONFIG_HOME/systemd/user" "$DATA_HOME/applications" \
  "$DATA_HOME/icons/hicolor/scalable/apps" "$PLUGIN_ROOT" "$BACKUP_DIR" "$RELEASES_ROOT"

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

old_source_repo=""
if [[ -f $INSTALL_RECORD ]]; then
  old_source_repo=$(jq -r '.sourceRepo // ""' "$INSTALL_RECORD" 2>/dev/null || true)
fi

owned_plugin_link() {
  [[ -L $PLUGIN_PATH ]] || return 1
  local target
  target=$(readlink -- "$PLUGIN_PATH")
  [[ $target == "$CURRENT_LINK/plugin" ]] && return 0
  [[ -n $old_source_repo && $target == "$old_source_repo/integration/omarchy-plugin" ]] && return 0
  [[ $target == "$REPO/integration/omarchy-plugin" ]]
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
  if ! owned_plugin_link; then backup_path "$PLUGIN_PATH" bmw.media; fi
  if [[ -d $PLUGIN_PATH && ! -L $PLUGIN_PATH ]]; then rm -r -- "$PLUGIN_PATH"
  else rm -f -- "$PLUGIN_PATH"
  fi
fi

# Retire the MusicKit prototype runtime during upgrades without touching credentials.
systemctl --user disable --now omarchy-applemusicplayer.service >/dev/null 2>&1 || true
rm -f -- "$SERVICE_PATH" "$BIN_HOME/omarchy-music-mini" "$BIN_HOME/omarchy-applemusicctl"
systemctl --user daemon-reload

runtime_root=$REPO
plugin_target="$REPO/integration/omarchy-plugin"
music_target="$REPO/bin/omarchy-music"
uninstall_target="$REPO/scripts/uninstall.sh"
icon_target="$REPO/assets/apple-music.svg"

if [[ $MODE == copy ]]; then
  version_root="$RELEASES_ROOT/$VERSION"
  mkdir -p "$version_root"
  stage=$(mktemp -d "$version_root/.staging-$STAMP.XXXXXX")
  release_root="$version_root/$STAMP"
  mkdir -p "$stage/plugin" "$stage/bin" "$stage/assets"
  cp -a -- "$REPO/integration/omarchy-plugin/." "$stage/plugin/"
  install -m 0755 "$REPO/bin/omarchy-music" "$stage/bin/omarchy-music"
  install -m 0755 "$REPO/scripts/uninstall.sh" "$stage/bin/omarchy-applemusicplayer-uninstall"
  install -m 0644 "$REPO/assets/apple-music.svg" "$stage/assets/apple-music.svg"
  mv -- "$stage" "$release_root"

  current_temp="$INSTALL_ROOT/.current-$STAMP"
  ln -s -- "$release_root" "$current_temp"
  mv -Tf -- "$current_temp" "$CURRENT_LINK"

  runtime_root=$release_root
  plugin_target="$CURRENT_LINK/plugin"
  music_target="$CURRENT_LINK/bin/omarchy-music"
  uninstall_target="$CURRENT_LINK/bin/omarchy-applemusicplayer-uninstall"
  icon_target="$CURRENT_LINK/assets/apple-music.svg"

  # Keep the active runtime and one immediately previous payload for rollback.
  current_real=$(readlink -f -- "$CURRENT_LINK")
  previous_kept=false
  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    [[ $candidate == "$current_real" ]] && continue
    if [[ $previous_kept == false ]]; then previous_kept=true; continue; fi
    case $candidate in
      "$RELEASES_ROOT"/*/*) rm -r -- "$candidate" ;;
    esac
  done < <(find "$RELEASES_ROOT" -mindepth 2 -maxdepth 2 -type d ! -name '.staging-*' -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)
  find "$RELEASES_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete
fi

ln -sfn -- "$music_target" "$BIN_HOME/omarchy-music"
ln -sfn -- "$uninstall_target" "$BIN_HOME/omarchy-applemusicplayer-uninstall"
ln -sfn -- "$icon_target" "$ICON_PATH"
ln -sfn -- "$plugin_target" "$PLUGIN_PATH"
install -m 0644 "$REPO/integration/Apple Music.desktop.in" "$DESKTOP_PATH"

record_temp=$(mktemp "$INSTALL_ROOT/.install.XXXXXX")
jq -n --arg mode "$MODE" --arg version "$VERSION" --arg sourceRepo "$REPO" --arg runtime "$runtime_root" \
  '{mode:$mode, version:$version, sourceRepo:$sourceRepo, runtime:$runtime}' > "$record_temp"
mv -f -- "$record_temp" "$INSTALL_RECORD"

install_managed_block "$BINDINGS" "$REPO/integration/hypr-bindings.lua"
strip_managed_block "$HYPRLAND"

shell_temp=$(mktemp "${SHELL_CONFIG}.omarchy-applemusicplayer.XXXXXX")
jq --slurpfile defaults "$REPO/integration/preferences.json" '
  .bar = (.bar // {})
  | .bar.layout = (.bar.layout // {})
  | ([.bar.layout[]?[]? | select(.id == "bmw.media")][0] // {}) as $existing
  | ({"id":"bmw.media"} + $defaults[0] + $existing + {"id":"bmw.media"}) as $media
  | .bar.layout |= with_entries(.value |= map(select(.id != "bmw.media")))
  | .bar.layout.center = (
      (.bar.layout.center // []) as $center
      | ($center | map(.id) | index("omarchy.clock")) as $clock
      | if $clock == null then $center + [$media]
        else $center[0:$clock] + [$media] + $center[$clock:]
        end
    )
' "$SHELL_CONFIG" > "$shell_temp"
chmod --reference="$SHELL_CONFIG" "$shell_temp"
mv -- "$shell_temp" "$SHELL_CONFIG"

update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
hyprctl reload >/dev/null
config_errors=$(hyprctl configerrors || true)
if [[ -n $config_errors ]]; then echo "$config_errors" >&2; exit 1; fi
omarchy restart shell

echo "Installed Omarchy Apple Music $VERSION ($MODE mode)."
echo "Runtime: $runtime_root"
echo "Backup: $BACKUP_DIR"
echo "Open Apple Music with SUPER + SHIFT + M."
