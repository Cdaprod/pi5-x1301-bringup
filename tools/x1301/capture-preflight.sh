#!/usr/bin/env bash
# Verify capture readiness without changes. Usage/example: capture-preflight.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
fail() { printf 'CAPTURE_READY=0\nREASON=%s\n' "$1"; exit "${2:-4}"; }
need media-ctl || exit 1; need v4l2-ctl || exit 1
MEDIA="$(find_rp1_cfe_media)" || fail DISCOVERY_ERROR 2
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || fail DISCOVERY_ERROR 2
POWER="$(get_control_value "$SUBDEV" power_present)"; [[ $POWER == 1 ]] || fail DISCONNECTED 3
TIMINGS="$(query_dv_timings "$SUBDEV")" || fail PRESENT_NO_SIGNAL 4
WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")"; [[ -n $VIDEO && -e $VIDEO ]] || fail CAPTURE_NODE_MISSING 5
GRAPH="$(media-ctl -d "$MEDIA" -p 2>&1)" || fail GRAPH_QUERY_FAILED 5
grep -Eq -- '-> "rp1-cfe-csi2_ch0":0 \[ENABLED' <<<"$GRAPH" || fail CAPTURE_LINK_DISABLED 5
grep -Eq "RGB888_1X24/${WIDTH}x${HEIGHT}|BGR888_1X24/${WIDTH}x${HEIGHT}" <<<"$GRAPH" || fail MEDIA_FORMAT_MISMATCH 5
v4l2-ctl -d "$VIDEO" --get-fmt-video >/dev/null 2>&1 || fail VIDEO_FORMAT_UNAVAILABLE 5
printf 'CAPTURE_READY=1\nMEDIA=%s\nSUBDEV=%s\nVIDEO=%s\nWIDTH=%s\nHEIGHT=%s\n' "$MEDIA" "$SUBDEV" "$VIDEO" "$WIDTH" "$HEIGHT"
