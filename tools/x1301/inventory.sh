#!/usr/bin/env bash
# Discover the X1301 pipeline. Usage: inventory.sh [--verbose]
# Example: ./tools/x1301/inventory.sh --verbose
set -uo pipefail
source "$(dirname "$0")/common.sh"
verbose=0
case "${1:-}" in "") ;; --verbose) verbose=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: usage: $0 [--verbose]" >&2; exit 1;; esac
need v4l2-ctl || exit 1; need media-ctl || exit 1
MEDIA="$(find_rp1_cfe_media)" || { echo 'X1301_FOUND=0'; exit 2; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo 'X1301_FOUND=0'; exit 2; }
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")"
printf 'X1301_FOUND=1\nMEDIA=%s\nSUBDEV=%s\nVIDEO=%s\n' "$MEDIA" "$SUBDEV" "${VIDEO:-unknown}"
if ((verbose)); then
  section DATE; date -Is
  section OS; cat /etc/os-release || true
  section KERNEL; uname -a
  section 'BOOT CONFIG'; grep -nE 'tc358743|camera|dtoverlay' /boot/firmware/config.txt 2>/dev/null || true
  section 'VIDEO DEVICES'; v4l2-ctl --list-devices || true
  section 'MEDIA GRAPH'; media-ctl -d "$MEDIA" -p || true
  section 'TC358743 SUBDEVICE'; v4l2-ctl -d "$SUBDEV" --all || true
fi
