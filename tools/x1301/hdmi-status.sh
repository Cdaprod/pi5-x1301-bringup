#!/usr/bin/env bash
# Report TC358743 connection and timing state.
# Usage: ./tools/x1301/hdmi-status.sh
# Example: ./tools/x1301/hdmi-status.sh; echo $?
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
need media-ctl || exit 1; need v4l2-ctl || exit 1
MEDIA="$(find_rp1_cfe_media)" || { echo "ERROR: RP1 CFE/TC358743 media graph not found" >&2; exit 2; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo "ERROR: TC358743 subdevice not found" >&2; exit 2; }
VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")"
POWER_PRESENT="$(get_control_value "$SUBDEV" power_present)"
AUDIO_PRESENT="$(get_control_value "$SUBDEV" audio_present)"
AUDIO_SAMPLING_RATE="$(get_control_value "$SUBDEV" audio_sampling_rate)"
printf 'MEDIA=%s\nSUBDEV=%s\nVIDEO=%s\n' "$MEDIA" "$SUBDEV" "${VIDEO:-unknown}"
printf 'POWER_PRESENT=%s\nAUDIO_PRESENT=%s\nAUDIO_SAMPLING_RATE=%s\n' \
  "${POWER_PRESENT:-unknown}" "${AUDIO_PRESENT:-unknown}" "${AUDIO_SAMPLING_RATE:-unknown}"
if TIMINGS="$(query_dv_timings "$SUBDEV")"; then
  WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
  PIXEL_CLOCK="$(awk -F: '/Pixelclock:|Pixel clock:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' <<<"$TIMINGS")"
  FPS="$(parse_frame_rate "$TIMINGS")"
  printf 'SIGNAL=LOCKED\nDV_TIMINGS=LOCKED\nACTIVE_WIDTH=%s\nACTIVE_HEIGHT=%s\nFPS=%s\nPIXEL_CLOCK=%s\nSTATE=LOCKED\n' \
    "$WIDTH" "$HEIGHT" "${FPS:-unknown}" "${PIXEL_CLOCK:-unknown}"
  printf 'TIMING_DETAILS:\n%s\n' "$TIMINGS"
  exit 0
fi
if [[ $POWER_PRESENT == 1 ]]; then SIGNAL=PRESENT_NO_SIGNAL; else SIGNAL=DISCONNECTED; fi
printf 'SIGNAL=%s\nDV_TIMINGS=NO_LINK\nACTIVE_WIDTH=unknown\nACTIVE_HEIGHT=unknown\nFPS=unknown\nPIXEL_CLOCK=unknown\nSTATE=NO_SIGNAL\n' "$SIGNAL"
printf 'TIMING_DETAILS:\n%s\n' "$TIMINGS"
exit 3
