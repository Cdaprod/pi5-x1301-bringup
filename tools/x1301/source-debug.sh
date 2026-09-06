#!/usr/bin/env bash
# Diagnose HDMI source negotiation. Usage/example: ./tools/x1301/source-debug.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
need media-ctl || exit 1; need v4l2-ctl || exit 1
MEDIA="$(find_rp1_cfe_media)" || { echo 'SOURCE_STATE=ERROR'; exit 2; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo 'SOURCE_STATE=ERROR'; exit 2; }
POWER="$(get_control_value "$SUBDEV" power_present)"; AUDIO="$(get_control_value "$SUBDEV" audio_present)"
if LIVE="$(query_dv_timings "$SUBDEV")"; then locked=1; else locked=0; fi
STATE="$(classify_signal_state "$POWER" "$locked")"
case "$STATE" in LOCKED) interpretation='Live HDMI timings are locked.';; PRESENT_NO_SIGNAL) interpretation='HDMI source detected electrically, but no live timings are locked.';; DISCONNECTED) interpretation='No HDMI source power is detected.';; esac
printf 'SOURCE_STATE=%s\nPOWER_PRESENT=%s\nAUDIO_PRESENT=%s\n' "$STATE" "${POWER:-unknown}" "${AUDIO:-unknown}"
printf 'LIVE_TIMING_QUERY:\n%s\nCURRENT_STORED_TIMING:\n' "${LIVE:-NO_LINK}"
v4l2-ctl -d "$SUBDEV" --get-dv-timings 2>&1 || true
if v4l2-ctl -d "$SUBDEV" --get-edid >/dev/null 2>&1; then echo 'EDID_STATE=QUERYABLE'; else echo 'EDID_STATE=UNKNOWN'; fi
printf 'INTERPRETATION="%s"\n' "$interpretation"
