#!/usr/bin/env bash
# Continuously watch HDMI state. Usage: hdmi-watch.sh [--interval SEC] [--configure] [--json] [--once]
# Example: sudo ./tools/x1301/hdmi-watch.sh --interval 1 --configure
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
interval=1; configure=0; json=0; once=0; configure_backoff="${X1301_CONFIGURE_BACKOFF:-10}"
while (($#)); do
  case "$1" in
    --interval) (($# >= 2)) || { echo 'ERROR: --interval requires seconds' >&2; exit 1; }; interval=$2; shift ;;
    --configure) configure=1 ;; --json) json=1 ;; --once) once=1 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;; *) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
  esac; shift
done
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'ERROR: interval must be numeric' >&2; exit 1; }
[[ $configure_backoff =~ ^[0-9]+$ ]] || { echo 'ERROR: configure backoff must be an integer' >&2; exit 1; }
need media-ctl || exit 1; need v4l2-ctl || exit 1

choose_state_file() {
  if [[ -n ${X1301_RUNTIME_STATE:-} ]]; then printf '%s\n' "$X1301_RUNTIME_STATE"
  elif [[ -d /run/x1301 && -w /run/x1301 ]] || mkdir -p /run/x1301 2>/dev/null; then printf '/run/x1301/state.env\n'
  else printf '%s/runtime-state.env\n' "$LOG_DIR"
  fi
}
write_state() {
  local file="$1" signal="$2" media="$3" subdev="$4" video="$5" width="$6" height="$7" fps="$8" configured="$9" changed="${10}"
  local tmp="${file}.tmp.$$"; mkdir -p "$(dirname "$file")"
  umask 022
  printf "X1301_STATUS_SCHEMA=1\nX1301_SIGNAL_STATE='%s'\nX1301_MEDIA='%s'\nX1301_SUBDEV='%s'\nX1301_VIDEO='%s'\nX1301_WIDTH='%s'\nX1301_HEIGHT='%s'\nX1301_FPS='%s'\nX1301_CONFIGURED='%s'\nX1301_LAST_CHANGE='%s'\n" \
    "$signal" "$media" "$subdev" "$video" "$width" "$height" "$fps" "$configured" "$changed" >"$tmp"
  mv -f "$tmp" "$file"
}
emit_event() {
  local event="$1" signal="$2" old_mode="$3" mode="$4" width="$5" height="$6" fps="$7"
  if ((json)); then
    printf '{"X1301_STATUS_SCHEMA":1,"event":%s,"signal_state":%s,"old_mode":%s,"mode":%s,"width":%s,"height":%s,"fps":%s}\n' \
      "$(json_string "$event")" "$(json_string "$signal")" "$(json_string "$old_mode")" "$(json_string "$mode")" "$(json_number_or_null "$width")" "$(json_number_or_null "$height")" "$(json_number_or_null "$fps")"
  elif [[ $event == MODE_CHANGE ]]; then printf 'X1301 EVENT MODE_CHANGE old=%s new=%s\n' "$old_mode" "$mode"
  elif [[ $event == LOCKED ]]; then printf 'X1301 EVENT LOCKED width=%s height=%s fps=%s\n' "$width" "$height" "${fps:-unknown}"
  else printf 'X1301 EVENT %s\n' "$event"
  fi
}

STATE_FILE="$(choose_state_file)"; CONFIGURE_COMMAND="${X1301_CONFIGURE_COMMAND:-$DIR/configure.sh}"
running=1; sleep_pid=""; previous_state=""; previous_mode=""; configured=0; last_change="$(date -Is)"; next_retry=0; polls=0
trap 'running=0; [[ -n $sleep_pid ]] && kill "$sleep_pid" 2>/dev/null || true' INT TERM
while ((running)); do
  state=ERROR; media=""; subdev=""; video=""; width=""; height=""; fps=""; mode=""; locked=0; power=""
  if media="$(find_rp1_cfe_media)" && subdev="$(find_tc358743_subdev "$media")"; then
    video="$(find_rp1_cfe_capture_node "$media")"; power="$(get_control_value "$subdev" power_present)"
    if [[ $power == 0 || $power == 1 ]]; then
      if timings="$(query_dv_timings "$subdev")"; then
        width="$(parse_active_width "$timings")"; height="$(parse_active_height "$timings")"; fps="$(parse_frame_rate "$timings")"
        [[ $width =~ ^[1-9][0-9]*$ && $height =~ ^[1-9][0-9]*$ ]] && locked=1
      fi
      state="$(classify_signal_state "$power" "$locked")"
    fi
  fi
  ((locked)) && mode="${width}x${height}"
  event="$state"; [[ $state == LOCKED && $previous_state == LOCKED && $mode != "$previous_mode" ]] && event=MODE_CHANGE
  transition=0; [[ $state != "$previous_state" || $event == MODE_CHANGE ]] && transition=1
  if ((transition)); then
    last_change="$(date -Is)"; [[ $event != LOCKED && $event != MODE_CHANGE ]] && configured=0
    emit_event "$event" "$state" "$previous_mode" "$mode" "$width" "$height" "$fps"
  fi
  now=$(date +%s)
  if ((configure)) && [[ $state == LOCKED ]] && { ((transition)) || { ((configured == 0)) && ((now >= next_retry)); }; }; then
    printf 'X1301 CONFIGURE START\n'
    if "$CONFIGURE_COMMAND"; then configured=1; next_retry=0; printf 'X1301 CONFIGURE OK\n'
    else rc=$?; configured=0; next_retry=$((now + configure_backoff)); printf 'X1301 CONFIGURE FAILED exit=%s retry_after=%s\n' "$rc" "$configure_backoff" >&2
    fi
  fi
  write_state "$STATE_FILE" "$state" "$media" "$subdev" "$video" "$width" "$height" "$fps" "$configured" "$last_change"
  previous_state="$state"; [[ -n $mode ]] && previous_mode="$mode"
  polls=$((polls + 1)); ((once)) && break; [[ ${HDMI_WATCH_MAX_POLLS:-0} -gt 0 && $polls -ge ${HDMI_WATCH_MAX_POLLS} ]] && break
  sleep "$interval" & sleep_pid=$!; wait "$sleep_pid" || true; sleep_pid=""
done
exit 0
