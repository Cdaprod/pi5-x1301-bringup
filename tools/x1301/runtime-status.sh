#!/usr/bin/env bash
# Read the watcher's cached state without querying hardware. Usage: runtime-status.sh [--json]
# Example: ./tools/x1301/runtime-status.sh --json
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"; json=0
case "${1:-}" in "") ;; --json) json=1 ;; -h|--help) sed -n '2,3p' "$0"; exit 0 ;; *) echo "ERROR: usage: $0 [--json]" >&2; exit 1 ;; esac
if [[ -n ${X1301_RUNTIME_STATE:-} ]]; then state_file="$X1301_RUNTIME_STATE"
elif [[ -r /run/x1301/state.env ]]; then state_file=/run/x1301/state.env
else state_file="$LOG_DIR/runtime-state.env"; fi
[[ -r $state_file ]] || { echo "ERROR: watcher state not found: $state_file" >&2; exit 2; }
state_value() {
  local key="$1" value
  value="$(sed -n "s/^${key}=//p" "$state_file" | tail -n 1)"
  value=${value#\'}; value=${value%\'}; printf '%s' "$value"
}
schema="$(state_value X1301_STATUS_SCHEMA)"; signal="$(state_value X1301_SIGNAL_STATE)"; media="$(state_value X1301_MEDIA)"; subdev="$(state_value X1301_SUBDEV)"; video="$(state_value X1301_VIDEO)"
width="$(state_value X1301_WIDTH)"; height="$(state_value X1301_HEIGHT)"; fps="$(state_value X1301_FPS)"; configured="$(state_value X1301_CONFIGURED)"; changed="$(state_value X1301_LAST_CHANGE)"
[[ $schema == 1 && $signal =~ ^(DISCONNECTED|PRESENT_NO_SIGNAL|LOCKED|ERROR)$ ]] || { echo 'ERROR: malformed watcher state' >&2; exit 3; }
if ((json)); then
  printf '{\n  "X1301_STATUS_SCHEMA": 1,\n  "signal_state": %s,\n  "media": %s,\n  "subdev": %s,\n  "video": %s,\n  "width": %s,\n  "height": %s,\n  "fps": %s,\n  "configured": %s,\n  "last_change": %s\n}\n' \
    "$(json_string "$signal")" "$(json_string "$media")" "$(json_string "$subdev")" "$(json_string "$video")" "$(json_number_or_null "$width")" "$(json_number_or_null "$height")" "$(json_number_or_null "$fps")" "$(json_bool "$configured")" "$(json_string "$changed")"
else
  printf 'SIGNAL=%s\nMEDIA=%s\nSUBDEV=%s\nVIDEO=%s\nWIDTH=%s\nHEIGHT=%s\nFPS=%s\nCONFIGURED=%s\nLAST_CHANGE=%s\n' "$signal" "$media" "$subdev" "$video" "${width:-unknown}" "${height:-unknown}" "${fps:-unknown}" "$configured" "$changed"
fi
