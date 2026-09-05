#!/usr/bin/env bash
# Configure the RP1 CFE route for the currently locked HDMI mode.
# Usage: sudo ./tools/x1301/configure.sh [--load-edid]
# Example: sudo ./tools/x1301/configure.sh --load-edid
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/common.sh"
need media-ctl; need v4l2-ctl; need awk
[[ $EUID -eq 0 || ${X1301_ALLOW_NONROOT:-0} == 1 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }

load=0
case "${1:-}" in "") ;; --load-edid) load=1 ;; -h|--help) sed -n '2,4p' "$0"; exit 0 ;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac
MEDIA="$(find_rp1_cfe_media)" || { echo "ERROR: RP1 CFE graph containing TC358743 not found" >&2; exit 2; }
GRAPH="$(media-ctl -d "$MEDIA" -p)"
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo "ERROR: TC358743 entity has no subdevice" >&2; exit 3; }
if (( load )); then "$DIR/load-edid.sh"; fi
TIMINGS="$(query_dv_timings "$SUBDEV")" || { echo "$TIMINGS" >&2; echo "ERROR: HDMI has no valid timings" >&2; exit 4; }
WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
[[ $WIDTH =~ ^[1-9][0-9]*$ && $HEIGHT =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: invalid active dimensions" >&2; exit 6; }
VIDEO="$(find_entity_node "$GRAPH" 'rp1-cfe-csi2_ch0')"
[[ -n "$VIDEO" ]] || { echo "ERROR: capture entity not found in owning graph" >&2; exit 7; }

v4l2-ctl -d "$SUBDEV" --set-dv-bt-timings=query
media-ctl -d "$MEDIA" -r
media-ctl -d "$MEDIA" -l "'csi2':4 -> 'rp1-cfe-csi2_ch0':0 [1]"
for pad in 0 4; do media-ctl -d "$MEDIA" -V "'csi2':$pad [fmt:RGB888_1X24/${WIDTH}x${HEIGHT} field:none colorspace:srgb]"; done
v4l2-ctl -d "$VIDEO" --set-fmt-video="width=$WIDTH,height=$HEIGHT,pixelformat=RGB3"

printf '%s\n' "$VIDEO" >"$LOG_DIR/last-video-node.txt"
cat >"$LOG_DIR/last-mode.env" <<EOF
X1301_MEDIA='$MEDIA'
X1301_SUBDEV='$SUBDEV'
X1301_VIDEO='$VIDEO'
X1301_WIDTH='$WIDTH'
X1301_HEIGHT='$HEIGHT'
X1301_PIXELFORMAT='RGB3'
EOF
printf 'X1301_STATUS=CONFIGURED\nMEDIA=%s\nSUBDEV=%s\nVIDEO=%s\nWIDTH=%s\nHEIGHT=%s\n' "$MEDIA" "$SUBDEV" "$VIDEO" "$WIDTH" "$HEIGHT"
