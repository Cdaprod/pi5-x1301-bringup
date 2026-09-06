#!/usr/bin/env bash
# Report live HDMI state. Usage: hdmi-status.sh [--json] [--verbose]
# Example: ./tools/x1301/hdmi-status.sh --json
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
json=0; verbose=0
while (($#)); do case "$1" in --json) json=1;; --verbose) verbose=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
need media-ctl || exit 1; need v4l2-ctl || exit 1
MEDIA="$(find_rp1_cfe_media)" || { ((json)) && printf '{"X1301_STATUS_SCHEMA":1,"signal_state":"ERROR","error":"media discovery failed"}\n'; echo "ERROR: RP1 CFE/TC358743 media graph not found" >&2; exit 2; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo "ERROR: TC358743 subdevice not found" >&2; exit 2; }
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")"; POWER="$(get_control_value "$SUBDEV" power_present)"
AUDIO="$(get_control_value "$SUBDEV" audio_present)"; RATE="$(get_control_value "$SUBDEV" audio_sampling_rate)"
locked=0; TIMINGS=""; WIDTH=""; HEIGHT=""; PIXELCLOCK=""; FPS=""
if TIMINGS="$(query_dv_timings "$SUBDEV")"; then
  WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
  [[ $WIDTH =~ ^[1-9][0-9]*$ && $HEIGHT =~ ^[1-9][0-9]*$ ]] && locked=1
  PIXELCLOCK="$(awk -F: '/Pixelclock:|Pixel clock:/ { gsub(/[^0-9].*/, "", $2); gsub(/[[:space:]]/, "", $2); print $2; exit }' <<<"$TIMINGS")"
  FPS="$(parse_frame_rate "$TIMINGS")"
fi
STATE="$(classify_signal_state "$POWER" "$locked")"
if ((json)); then
  printf '{\n  "X1301_STATUS_SCHEMA": 1,\n  "media": %s,\n  "subdev": %s,\n  "video": %s,\n' "$(json_string "$MEDIA")" "$(json_string "$SUBDEV")" "$(json_string "$VIDEO")"
  printf '  "power_present": %s,\n  "audio_present": %s,\n  "audio_sampling_rate": %s,\n' "$(json_bool "$POWER")" "$(json_bool "$AUDIO")" "$(json_number_or_null "$RATE")"
  printf '  "signal_state": %s,\n  "timings_locked": %s,\n  "width": %s,\n  "height": %s,\n  "fps": %s,\n  "pixelclock": %s\n}\n' "$(json_string "$STATE")" "$(json_bool "$locked")" "$(json_number_or_null "$WIDTH")" "$(json_number_or_null "$HEIGHT")" "$(json_number_or_null "$FPS")" "$(json_number_or_null "$PIXELCLOCK")"
else
  printf 'MEDIA=%s\nSUBDEV=%s\nVIDEO=%s\nPOWER_PRESENT=%s\nAUDIO_PRESENT=%s\nAUDIO_SAMPLING_RATE=%s\nSIGNAL=%s\n' "$MEDIA" "$SUBDEV" "$VIDEO" "${POWER:-unknown}" "${AUDIO:-unknown}" "${RATE:-unknown}" "$STATE"
  ((locked)) && printf 'ACTIVE_WIDTH=%s\nACTIVE_HEIGHT=%s\nFPS=%s\nPIXELCLOCK=%s\n' "$WIDTH" "$HEIGHT" "${FPS:-unknown}" "${PIXELCLOCK:-unknown}"
fi
if ((verbose)); then printf '\nMEDIA_GRAPH:\n'; media-ctl -d "$MEDIA" -p; printf '\nSUBDEVICE:\n'; v4l2-ctl -d "$SUBDEV" --all || true; printf '\nLIVE_TIMINGS:\n%s\n' "${TIMINGS:-NO_LINK}"; fi
[[ $STATE == LOCKED ]] && exit 0; exit 3
