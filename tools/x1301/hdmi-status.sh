#!/usr/bin/env bash
# Report TC358743 connection and timing state.
# Usage: ./tools/x1301/hdmi-status.sh
# Example: ./tools/x1301/hdmi-status.sh; echo $?
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
need media-ctl || exit 1; need v4l2-ctl || exit 1
MEDIA="$(find_rp1_cfe_media)" || { echo "ERROR: RP1 CFE/TC358743 media graph not found" >&2; exit 2; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo "ERROR: TC358743 subdevice not found" >&2; exit 2; }
printf 'MEDIA=%s\nSUBDEV=%s\n' "$MEDIA" "$SUBDEV"
for control in power_present audio_sampling_rate audio_present; do
  value="$(get_control_value "$SUBDEV" "$control")"; printf '%s=%s\n' "$control" "${value:-unknown}"
done
if TIMINGS="$(query_dv_timings "$SUBDEV")"; then
  printf 'TIMINGS:\n%s\n' "$TIMINGS"
  WIDTH="$(parse_active_width "$TIMINGS")"; HEIGHT="$(parse_active_height "$TIMINGS")"
  PIXEL_CLOCK="$(awk -F: '/Pixelclock:|Pixel clock:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }' <<<"$TIMINGS")"
  printf 'ACTIVE_WIDTH=%s\nACTIVE_HEIGHT=%s\nPIXEL_CLOCK=%s\nSTATE=LOCKED\n' "$WIDTH" "$HEIGHT" "${PIXEL_CLOCK:-unknown}"
  exit 0
fi
printf 'TIMINGS:\n%s\nACTIVE_WIDTH=unknown\nACTIVE_HEIGHT=unknown\nPIXEL_CLOCK=unknown\nSTATE=NO_SIGNAL\n' "$TIMINGS"
exit 3
