#!/usr/bin/env bash
# Poll HDMI once per second and print state transitions only.
# Usage: ./tools/x1301/hdmi-watch.sh [--configure]
# Example: sudo ./tools/x1301/hdmi-watch.sh --configure
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
need media-ctl || exit 1; need v4l2-ctl || exit 1
configure=0; [[ ${1:-} == --configure ]] && configure=1
[[ $# -le 1 && (${1:-} == --configure || $# == 0) ]] || { echo "ERROR: usage: $0 [--configure]" >&2; exit 1; }
previous=""; previous_mode=""; polls=0
while :; do
  state=DISCONNECTED; mode=""
  if MEDIA="$(find_rp1_cfe_media)" && SUBDEV="$(find_tc358743_subdev "$MEDIA")"; then
    power="$(get_control_value "$SUBDEV" power_present)"
    if timings="$(query_dv_timings "$SUBDEV")"; then
      width="$(parse_active_width "$timings")"; height="$(parse_active_height "$timings")"
      if [[ $width =~ ^[1-9][0-9]*$ && $height =~ ^[1-9][0-9]*$ ]]; then state="LOCKED ${width}x${height}"; mode="${width}x${height}"; fi
    elif [[ $power == 1 ]]; then state=PRESENT_NO_SIGNAL; fi
  fi
  if [[ $state != "$previous" ]]; then
    if [[ $state == LOCKED* && $previous == LOCKED* && $mode != "$previous_mode" ]]; then printf 'MODE_CHANGE %s\n' "$mode"; else printf '%s\n' "$state"; fi
    if (( configure )) && [[ $state == LOCKED* ]] && [[ $previous != "$state" ]]; then "$DIR/configure.sh" || echo "ERROR: configure failed" >&2; fi
  fi
  previous="$state"; [[ -n "$mode" ]] && previous_mode="$mode"
  polls=$((polls + 1)); [[ ${HDMI_WATCH_MAX_POLLS:-0} -gt 0 && $polls -ge ${HDMI_WATCH_MAX_POLLS} ]] && break
  sleep 1
done
