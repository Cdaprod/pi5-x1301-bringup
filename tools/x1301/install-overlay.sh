#!/usr/bin/env bash
# Idempotently install the X1301 CAM0 video and audio overlays.
# Usage: sudo ./tools/x1301/install-overlay.sh
# Example: sudo ./tools/x1301/install-overlay.sh
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $EUID -eq 0 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }
CFG=${X1301_BOOT_CONFIG:-/boot/firmware/config.txt}
[[ -f "$CFG" ]] || { echo "ERROR: $CFG not found" >&2; exit 2; }
BACKUP="${CFG}.pre-x1301-$(timestamp)"; cp "$CFG" "$BACKUP"
# CAM1/four-lane configurations are electrically incompatible with this setup.
sed -i -E '/^[[:space:]]*dtoverlay=tc358743,(4lane=1|cam1)(,.*)?[[:space:]]*$/d' "$CFG"
for line in 'dtoverlay=tc358743,cam0' 'dtoverlay=tc358743-audio'; do
  grep -qxF "$line" "$CFG" || printf '%s\n' "$line" >>"$CFG"
done
if cmp -s "$CFG" "$BACKUP"; then
  rm "$BACKUP"; echo 'X1301 overlays already correct. REBOOT_REQUIRED=0'
else
  echo "X1301 CAM0 overlays installed. Backup: $BACKUP"; echo 'REBOOT_REQUIRED=1'
fi
