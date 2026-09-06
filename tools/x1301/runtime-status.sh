#!/usr/bin/env bash
# Read the watcher's cached state without querying hardware. Usage: runtime-status.sh [--json]
# Example: ./tools/x1301/runtime-status.sh --json
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"; json=0
case "${1:-}" in "") ;; --json) json=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: usage: $0 [--json]" >&2; exit 1;; esac
if [[ -n ${X1301_RUNTIME_STATE:-} ]]; then state_file="$X1301_RUNTIME_STATE"; elif [[ -r /run/x1301/state.env ]]; then state_file=/run/x1301/state.env; else state_file="$LOG_DIR/runtime-state.env"; fi
[[ -r $state_file ]] || { echo "ERROR: watcher state not found: $state_file" >&2; exit 2; }
state_value() { local value; value="$(sed -n "s/^X1301_$1=//p" "$state_file" | tail -n 1)"; value=${value#\'}; value=${value%\'}; printf '%s' "$value"; }
for key in STATUS_SCHEMA SIGNAL_STATE MEDIA SUBDEV VIDEO WIDTH HEIGHT FPS CONFIGURED LAST_CHANGE POWER_PRESENT TIMINGS_LOCKED AUDIO_PRESENT AUDIO_SAMPLING_RATE PIXELCLOCK_HZ PIXELFORMAT MODE_ID MODE_GENERATION DRIVER RP1_CFE_DETECTED ERROR; do eval "$key=\$(state_value $key)"; done
[[ $STATUS_SCHEMA == 1 && $SIGNAL_STATE =~ ^(DISCONNECTED|PRESENT_NO_SIGNAL|MODE_CHANGE|LOCKED|ERROR)$ ]] || { echo 'ERROR: malformed watcher state' >&2; exit 3; }
if ((json)); then
  printf '{\n  "X1301_STATUS_SCHEMA": 1,\n  "signal_state": %s,\n  "media": %s,\n  "subdev": %s,\n  "video": %s,\n  "width": %s,\n  "height": %s,\n  "fps": %s,\n  "configured": %s,\n  "last_change": %s,\n  "power_present": %s,\n  "timings_locked": %s,\n  "audio_present": %s,\n  "audio_sampling_rate": %s,\n  "pixelclock_hz": %s,\n  "pixelformat": %s,\n  "mode_id": %s,\n  "mode_generation": %s,\n  "driver": %s,\n  "rp1_cfe_detected": %s,\n  "error": %s\n}\n' \
    "$(json_string "$SIGNAL_STATE")" "$(json_string "$MEDIA")" "$(json_string "$SUBDEV")" "$(json_string "$VIDEO")" "$(json_number_or_null "$WIDTH")" "$(json_number_or_null "$HEIGHT")" "$(json_number_or_null "$FPS")" "$(json_bool "$CONFIGURED")" "$(json_string "$LAST_CHANGE")" "$(json_bool "$POWER_PRESENT")" "$(json_bool "$TIMINGS_LOCKED")" "$(json_bool "$AUDIO_PRESENT")" "$(json_number_or_null "$AUDIO_SAMPLING_RATE")" "$(json_number_or_null "$PIXELCLOCK_HZ")" "$(json_string "$PIXELFORMAT")" "$(json_string "$MODE_ID")" "$(json_number_or_null "$MODE_GENERATION")" "$(json_string "$DRIVER")" "$(json_bool "$RP1_CFE_DETECTED")" "$(json_string "$ERROR")"
else
  for key in SIGNAL_STATE MEDIA SUBDEV VIDEO WIDTH HEIGHT FPS CONFIGURED LAST_CHANGE POWER_PRESENT TIMINGS_LOCKED AUDIO_PRESENT AUDIO_SAMPLING_RATE PIXELCLOCK_HZ PIXELFORMAT MODE_ID MODE_GENERATION DRIVER RP1_CFE_DETECTED ERROR; do eval "value=\${$key}"; printf '%s=%s\n' "$key" "$value"; done
fi
