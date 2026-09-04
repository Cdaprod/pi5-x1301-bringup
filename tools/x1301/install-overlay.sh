#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

CFG=/boot/firmware/config.txt
[[ -f "$CFG" ]] || { echo "ERROR: $CFG not found"; exit 1; }
BACKUP="${CFG}.pre-x1301-$(timestamp)"
changed=0

cp "$CFG" "$BACKUP"

grep -qE '^[[:space:]]*dtoverlay=tc358743,4lane=1[[:space:]]*$' "$CFG" || {
  printf '\n# Geekworm X1301 / TC358743 HDMI -> CSI-2\n%s\n' \
    'dtoverlay=tc358743,4lane=1' >> "$CFG"
  changed=1
}
grep -qE '^[[:space:]]*dtoverlay=tc358743-audio[[:space:]]*$' "$CFG" || {
  echo 'dtoverlay=tc358743-audio' >> "$CFG"
  changed=1
}

if (( changed )); then
  echo "X1301 overlays added."
  echo "Backup: $BACKUP"
  echo "REBOOT_REQUIRED=1"
  echo "Run: sudo reboot"
else
  rm -f "$BACKUP"
  echo "X1301 overlays already present; no change made."
  echo "REBOOT_REQUIRED=0"
fi
