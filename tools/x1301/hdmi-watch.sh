#!/usr/bin/env bash
# Publish and maintain the X1301 HDMI lifecycle. Usage: hdmi-watch.sh [--interval SEC] [--configure] [--json] [--once]
# Example: sudo ./tools/x1301/hdmi-watch.sh --interval 1 --configure
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
interval=1; configure=0; json=0; once=0; configure_backoff="${X1301_CONFIGURE_BACKOFF:-10}"
while (($#)); do case "$1" in
  --interval) (($# >= 2)) || { echo 'ERROR: --interval requires seconds' >&2; exit 1; }; interval=$2; shift;;
  --configure) configure=1;; --json) json=1;; --once) once=1;;
  -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;;
esac; shift; done
[[ $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'ERROR: interval must be numeric' >&2; exit 1; }
[[ $configure_backoff =~ ^[0-9]+$ ]] || { echo 'ERROR: configure backoff must be an integer' >&2; exit 1; }
need media-ctl || exit 1; need v4l2-ctl || exit 1
choose_state_file() {
  if [[ -n ${X1301_RUNTIME_STATE:-} ]]; then printf '%s\n' "$X1301_RUNTIME_STATE"
  elif [[ -d /run/x1301 && -w /run/x1301 ]] || mkdir -p /run/x1301 2>/dev/null; then printf '/run/x1301/state.env\n'
  else printf '%s/runtime-state.env\n' "$LOG_DIR"; fi
}
state_safe() { local v="$1"; v=${v//$'\n'/ }; v=${v//\'/}; printf '%s' "$v"; }
write_state() {
  local file="$1" tmp="${1}.tmp.$$"
  mkdir -p "$(dirname "$file")"; umask 022
  {
    printf 'X1301_STATUS_SCHEMA=1\n'
    for key in SIGNAL_STATE MEDIA SUBDEV VIDEO WIDTH HEIGHT FPS CONFIGURED LAST_CHANGE POWER_PRESENT TIMINGS_LOCKED AUDIO_PRESENT AUDIO_SAMPLING_RATE PIXELCLOCK_HZ PIXELFORMAT MODE_ID MODE_GENERATION DRIVER RP1_CFE_DETECTED ERROR; do
      eval "value=\${$key:-}"; printf "X1301_%s='%s'\n" "$key" "$(state_safe "$value")"
    done
  } >"$tmp"
  mv -f "$tmp" "$file"
}
emit_event() {
  local event="$1"
  if ((json)); then
    printf '{"X1301_STATUS_SCHEMA":1,"event":%s,"signal_state":%s,"mode_id":%s,"mode_generation":%s,"media":%s,"subdev":%s,"video":%s,"width":%s,"height":%s,"fps":%s,"pixelclock_hz":%s,"configured":%s,"error":%s}\n' \
      "$(json_string "$event")" "$(json_string "$SIGNAL_STATE")" "$(json_string "$MODE_ID")" "$MODE_GENERATION" "$(json_string "$MEDIA")" "$(json_string "$SUBDEV")" "$(json_string "$VIDEO")" "$(json_number_or_null "$WIDTH")" "$(json_number_or_null "$HEIGHT")" "$(json_number_or_null "$FPS")" "$(json_number_or_null "$PIXELCLOCK_HZ")" "$(json_bool "$CONFIGURED")" "$(json_string "$ERROR")"
  else printf 'X1301 EVENT %s mode=%s generation=%s configured=%s%s\n' "$event" "${MODE_ID:-none}" "$MODE_GENERATION" "$CONFIGURED" "${ERROR:+ error=$ERROR}"; fi
}
STATE_FILE="$(choose_state_file)"; CONFIGURE_COMMAND="${X1301_CONFIGURE_COMMAND:-$DIR/configure.sh}"
running=1; sleep_pid=""; previous_observed=""; previous_identity=""; configured_identity=""; LAST_CHANGE="$(date -Is)"; MODE_GENERATION=0; next_retry=0; polls=0
trap 'running=0; [[ -n $sleep_pid ]] && kill "$sleep_pid" 2>/dev/null || true' INT TERM
while ((running)); do
  SIGNAL_STATE=ERROR; MEDIA=""; SUBDEV=""; VIDEO=""; WIDTH=""; HEIGHT=""; FPS=""; PIXELCLOCK_HZ=""; PIXELFORMAT=RGB3; MODE_ID=""; CONFIGURED=0
  POWER_PRESENT=0; TIMINGS_LOCKED=0; AUDIO_PRESENT=0; AUDIO_SAMPLING_RATE=""; DRIVER=""; RP1_CFE_DETECTED=0; ERROR='RP1 CFE/TC358743 media graph not found'
  if MEDIA="$(find_rp1_cfe_media)" && SUBDEV="$(find_tc358743_subdev "$MEDIA")"; then
    RP1_CFE_DETECTED=1; DRIVER=rp1-cfe; VIDEO="$(find_rp1_cfe_capture_node "$MEDIA")"
    POWER_PRESENT="$(get_control_value "$SUBDEV" power_present)"; AUDIO_PRESENT="$(get_control_value "$SUBDEV" audio_present)"; AUDIO_SAMPLING_RATE="$(get_control_value "$SUBDEV" audio_sampling_rate)"
    ERROR=""
    if [[ $POWER_PRESENT == 0 || $POWER_PRESENT == 1 ]]; then
      if timings="$(query_dv_timings "$SUBDEV")"; then
        WIDTH="$(parse_active_width "$timings")"; HEIGHT="$(parse_active_height "$timings")"; FPS="$(parse_frame_rate "$timings")"; PIXELCLOCK_HZ="$(parse_pixelclock "$timings")"
        if [[ $WIDTH =~ ^[1-9][0-9]*$ && $HEIGHT =~ ^[1-9][0-9]*$ && $PIXELCLOCK_HZ =~ ^[1-9][0-9]*$ ]]; then TIMINGS_LOCKED=1
        else ERROR='Malformed live DV timings'; fi
      fi
      SIGNAL_STATE="$(classify_signal_state "$POWER_PRESENT" "$TIMINGS_LOCKED")"
    else SIGNAL_STATE=ERROR; ERROR='Malformed power_present control'; fi
  fi
  observed_signal="$SIGNAL_STATE"
  ((TIMINGS_LOCKED)) && MODE_ID="${WIDTH}x${HEIGHT}@${FPS:-unknown}/${PIXELCLOCK_HZ}Hz/${PIXELFORMAT}"
  identity="$MEDIA|$SUBDEV|$VIDEO|$MODE_ID"; changed=0
  [[ $observed_signal != "$previous_observed" || $identity != "$previous_identity" ]] && changed=1
  if ((changed)); then
    LAST_CHANGE="$(date -Is)"; configured_identity=""; next_retry=0
    if [[ $SIGNAL_STATE == LOCKED ]]; then SIGNAL_STATE=MODE_CHANGE; MODE_GENERATION=$((MODE_GENERATION + 1)); fi
    emit_event "$SIGNAL_STATE"; write_state "$STATE_FILE"
  fi
  now=$(date +%s)
  if [[ $SIGNAL_STATE == MODE_CHANGE || $SIGNAL_STATE == LOCKED ]]; then
    if [[ $configured_identity == "$identity" ]]; then CONFIGURED=1; SIGNAL_STATE=LOCKED
    elif ((configure)) && ((now >= next_retry)); then
      SIGNAL_STATE=MODE_CHANGE; CONFIGURED=0; write_state "$STATE_FILE"; printf 'X1301 CONFIGURE START mode=%s\n' "$MODE_ID"
      if "$CONFIGURE_COMMAND"; then configured_identity="$identity"; CONFIGURED=1; SIGNAL_STATE=LOCKED; ERROR=""; next_retry=0; printf 'X1301 CONFIGURE OK\n'
      else rc=$?; ERROR="configuration failed (exit $rc)"; next_retry=$((now + configure_backoff)); printf 'X1301 CONFIGURE FAILED exit=%s retry_after=%s\n' "$rc" "$configure_backoff" >&2
      fi
    else SIGNAL_STATE=MODE_CHANGE; fi
  fi
  write_state "$STATE_FILE"
  previous_observed="$observed_signal"; previous_identity="$identity"
  polls=$((polls + 1)); ((once)) && break; [[ ${HDMI_WATCH_MAX_POLLS:-0} -gt 0 && $polls -ge ${HDMI_WATCH_MAX_POLLS} ]] && break
  sleep "$interval" & sleep_pid=$!; wait "$sleep_pid" || true; sleep_pid=""
done
