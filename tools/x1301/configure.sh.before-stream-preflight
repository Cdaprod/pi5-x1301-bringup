#!/usr/bin/env bash
# Configure RP1 CFE for live HDMI. Usage: configure.sh [--dry-run] [--load-edid]
# Example: sudo ./tools/x1301/configure.sh --dry-run
# Exit: 2 discovery, 3 disconnected, 4 present/no signal, 5 graph configuration.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
dry=0; load=0
while (($#)); do case "$1" in --dry-run) dry=1;; --load-edid) load=1;; -h|--help) sed -n '2,4p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
((dry && load)) && { echo 'ERROR: --dry-run cannot load EDID' >&2; exit 1; }
need media-ctl || exit 1; need v4l2-ctl || exit 1
((dry)) || [[ $EUID -eq 0 || ${X1301_ALLOW_NONROOT:-0} == 1 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }
MEDIA="$(find_rp1_cfe_media)" || { echo 'X1301_STATUS=ERROR'; exit 2; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo 'X1301_STATUS=ERROR'; exit 2; }
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")" || true
POWER="$(get_control_value "$SUBDEV" power_present)"
if ((load)); then "$DIR/load-edid.sh"; sleep 1; fi
TIMINGS=""
attempts=1; ((load)) && attempts=20
for ((attempt=1; attempt<=attempts; attempt++)); do
  TIMINGS="$(query_dv_timings "$SUBDEV")" && break
  ((attempt < attempts)) && sleep 1
done
POWER="$(get_control_value "$SUBDEV" power_present)"
if [[ -z $TIMINGS ]]; then
  [[ $POWER == 1 ]] && { echo 'X1301_STATUS=PRESENT_NO_SIGNAL'; exit 4; }
  echo 'X1301_STATUS=DISCONNECTED'; exit 3
fi
WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
[[ $WIDTH =~ ^[1-9][0-9]*$ && $HEIGHT =~ ^[1-9][0-9]*$ ]] || { echo 'X1301_STATUS=ERROR'; exit 4; }
[[ -n "$VIDEO" ]] || { echo 'X1301_STATUS=ERROR'; exit 2; }
commands=("v4l2-ctl -d $SUBDEV --set-dv-bt-timings=query" "media-ctl -d $MEDIA -r" "media-ctl -d $MEDIA -l csi2:4-to-rp1-cfe-csi2_ch0:0" "media-ctl -d $MEDIA -V csi2:0=RGB888_1X24/${WIDTH}x${HEIGHT}" "media-ctl -d $MEDIA -V csi2:4=RGB888_1X24/${WIDTH}x${HEIGHT}" "v4l2-ctl -d $VIDEO --set-fmt-video=width=$WIDTH,height=$HEIGHT,pixelformat=RGB3")
printf 'MEDIA=%s\nSUBDEV=%s\nVIDEO=%s\nWIDTH=%s\nHEIGHT=%s\n' "$MEDIA" "$SUBDEV" "$VIDEO" "$WIDTH" "$HEIGHT"
if ((dry)); then printf 'DRY_RUN=1\n'; printf 'COMMAND=%s\n' "${commands[@]}"; exit 0; fi
v4l2-ctl -d "$SUBDEV" --set-dv-bt-timings=query || exit 5
media-ctl -d "$MEDIA" -r || exit 5
media-ctl -d "$MEDIA" -l "'csi2':4 -> 'rp1-cfe-csi2_ch0':0 [1]" || exit 5
for pad in 0 4; do media-ctl -d "$MEDIA" -V "'csi2':$pad [fmt:RGB888_1X24/${WIDTH}x${HEIGHT} field:none colorspace:srgb]" || exit 5; done
v4l2-ctl -d "$VIDEO" --set-fmt-video="width=$WIDTH,height=$HEIGHT,pixelformat=RGB3" || exit 5
printf '%s\n' "$VIDEO" >"$LOG_DIR/last-video-node.txt"
printf "X1301_MEDIA='%s'\nX1301_SUBDEV='%s'\nX1301_VIDEO='%s'\nX1301_WIDTH='%s'\nX1301_HEIGHT='%s'\nX1301_PIXELFORMAT='RGB3'\n" "$MEDIA" "$SUBDEV" "$VIDEO" "$WIDTH" "$HEIGHT" >"$LOG_DIR/last-mode.env"
echo 'X1301_STATUS=CONFIGURED'
