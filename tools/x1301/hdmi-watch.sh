#!/usr/bin/env bash
# Watch HDMI transitions. Usage: hdmi-watch.sh [--interval SEC] [--configure] [--json] [--once]
# Example: sudo ./tools/x1301/hdmi-watch.sh --interval 1 --configure
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
interval=1; configure=0; json=0; once=0
while (($#)); do case "$1" in --interval) (($# >= 2)) || { echo 'ERROR: --interval needs a value' >&2; exit 1; }; interval=$2; shift;; --configure) configure=1;; --json) json=1;; --once) once=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'ERROR: interval must be numeric' >&2; exit 1; }
need media-ctl || exit 1; need v4l2-ctl || exit 1
running=1; trap 'running=0' INT TERM
previous_state=""; previous_mode=""; polls=0
while ((running)); do
  state=ERROR; mode=""; media=""; subdev=""; video=""; width=""; height=""
  if media="$(find_rp1_cfe_media)" && subdev="$(find_tc358743_subdev "$media")"; then
    video="$(find_rp1_cfe_capture_node "$media")"; power="$(get_control_value "$subdev" power_present)"; locked=0
    if timings="$(query_dv_timings "$subdev")"; then width="$(parse_active_width "$timings")"; height="$(parse_active_height "$timings")"; [[ $width =~ ^[1-9][0-9]*$ && $height =~ ^[1-9][0-9]*$ ]] && locked=1; fi
    state="$(classify_signal_state "$power" "$locked")"; ((locked)) && mode="${width}x${height}"
  fi
  event="$state"
  [[ $state == LOCKED && $previous_state == LOCKED && $mode != "$previous_mode" ]] && event=MODE_CHANGE
  if [[ $state != "$previous_state" || $event == MODE_CHANGE ]]; then
    if ((json)); then printf '{"X1301_STATUS_SCHEMA":1,"event":%s,"signal_state":%s,"media_node":%s,"subdev_node":%s,"video_node":%s,"width":%s,"height":%s}\n' "$(json_string "$event")" "$(json_string "$state")" "$(json_string "$media")" "$(json_string "$subdev")" "$(json_string "$video")" "$(json_number_or_null "$width")" "$(json_number_or_null "$height")"
    elif [[ $event == LOCKED || $event == MODE_CHANGE ]]; then printf '%s %s\n' "$event" "$mode"; else printf '%s\n' "$event"; fi
    if ((configure)) && [[ $event == LOCKED || $event == MODE_CHANGE ]]; then "$DIR/configure.sh" || echo 'ERROR: configure failed' >&2; fi
  fi
  previous_state="$state"; [[ -n $mode ]] && previous_mode="$mode"
  polls=$((polls+1)); ((once)) && break; [[ ${HDMI_WATCH_MAX_POLLS:-0} -gt 0 && $polls -ge ${HDMI_WATCH_MAX_POLLS} ]] && break
  sleep "$interval" & wait $! || true
done
exit 0
