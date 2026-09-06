#!/usr/bin/env bash
# Capture graph-owned RGB frames. Usage: capture-test.sh [--frames N] [--output RAW] [--png PNG]
# Example: sudo capture-test.sh --frames 1 --output /tmp/frame.raw --png /tmp/frame.png
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
frames=2; output=""; png=""
while (($#)); do case "$1" in --frames) frames=${2:?}; shift;; --output) output=${2:?}; shift;; --png) png=${2:?}; shift;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
[[ $frames =~ ^[1-9][0-9]*$ ]] || { echo 'ERROR: frames must be positive' >&2; exit 1; }
need media-ctl; need v4l2-ctl
MEDIA="$(find_rp1_cfe_media)" || exit 2; SUBDEV="$(find_tc358743_subdev "$MEDIA")" || exit 2
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")"; [[ -n $VIDEO ]] || exit 2
TIMINGS="$(query_dv_timings "$SUBDEV")" || { echo 'ERROR: live timings not locked' >&2; exit 3; }
WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
if [[ -r $LOG_DIR/last-mode.env ]]; then source "$LOG_DIR/last-mode.env"; [[ ${X1301_VIDEO:-} == "$VIDEO" ]] && { WIDTH=${X1301_WIDTH:-$WIDTH}; HEIGHT=${X1301_HEIGHT:-$HEIGHT}; }; fi
output=${output:-$LOG_DIR/capture-$(timestamp).raw}; mkdir -p "$(dirname "$output")"; [[ -z $png ]] || mkdir -p "$(dirname "$png")"
v4l2-ctl -d "$VIDEO" --set-fmt-video="width=$WIDTH,height=$HEIGHT,pixelformat=RGB3" --stream-mmap=4 --stream-skip=3 --stream-count="$frames" --stream-to="$output" --stream-poll
printf 'CAPTURE_STATUS=SUCCESS\nRAW_PATH=%s\n' "$output"
if [[ -n $png ]]; then
  if command -v ffmpeg >/dev/null 2>&1; then ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size "${WIDTH}x${HEIGHT}" -i "$output" -frames:v 1 "$png" >/dev/null 2>&1; printf 'PNG_PATH=%s\n' "$png"
  else printf 'WARNING: ffmpeg unavailable; convert with: ffmpeg -f rawvideo -pixel_format rgb24 -video_size %sx%s -i %q -frames:v 1 %q\n' "$WIDTH" "$HEIGHT" "$output" "$png"; fi
fi
