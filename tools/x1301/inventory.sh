#!/usr/bin/env bash
set -u
source "$(dirname "$0")/common.sh"
need v4l2-ctl
need media-ctl

LOG="$LOG_DIR/inventory-$(timestamp).log"
exec > >(tee "$LOG") 2>&1

section "DATE"
date -Is
section "OS"
cat /etc/os-release || true
section "KERNEL"
uname -a
section "BOOT CONFIG"
grep -nE 'tc358743|camera|dtoverlay' /boot/firmware/config.txt 2>/dev/null || true
section "VIDEO DEVICES"
v4l2-ctl --list-devices || true
section "DEVICE NODES"
ls -l /dev/video* /dev/v4l-subdev* /dev/media* 2>/dev/null || true
section "MEDIA GRAPHS"
for m in /dev/media*; do
  [[ -e "$m" ]] || continue
  echo "----- $m -----"
  media-ctl -d "$m" -p || true
done
section "SUBDEVICES"
for d in /dev/v4l-subdev*; do
  [[ -e "$d" ]] || continue
  echo "----- $d -----"
  v4l2-ctl -d "$d" --all || true
done
section "AUTO-DETECTION"
echo "RP1 CFE media device:"
find_rp1_cfe_media || true
echo "TC358743 subdevice from owning entity:"
find_tc358743_subdev || true
MEDIA="$(find_rp1_cfe_media || true)"
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA" 2>/dev/null || true)"
echo "RP1 CFE primary capture node:"
echo "${VIDEO:-not found}"
if [[ -z "$VIDEO" ]]; then
  echo "Fallback capture candidates:"
  find_capture_candidates || true
fi
section "RESULT"
echo "Inventory complete."
echo "Log: $LOG"
