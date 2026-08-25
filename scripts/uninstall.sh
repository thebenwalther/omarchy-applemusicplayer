#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

systemctl --user disable --now omarchy-applemusicplayer.service 2>/dev/null || true
rm -f "$CONFIG_HOME/systemd/user/omarchy-applemusicplayer.service"
rm -f "$HOME/.local/bin/omarchy-music" "$HOME/.local/bin/omarchy-music-mini" "$HOME/.local/bin/omarchy-applemusicctl"
rm -f "$DATA_HOME/applications/Apple Music.desktop" "$DATA_HOME/icons/hicolor/scalable/apps/omarchy-applemusicplayer.svg"
[[ -L "$CONFIG_HOME/omarchy/plugins/bmw.media" ]] && rm "$CONFIG_HOME/omarchy/plugins/bmw.media"
systemctl --user daemon-reload

echo "Application links and service removed."
echo "Restore the timestamped Hyprland, shell, and bmw.media backups if you want the previous integration back."
echo "MusicKit credentials remain in ~/.config/omarchy-applemusicplayer until you remove them explicitly."
