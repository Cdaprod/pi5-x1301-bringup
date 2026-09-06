#!/usr/bin/env bash
# Fixture tests for common helpers. Usage/example: ./tests/test-common.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; source "$ROOT/tools/x1301/common.sh"
graph="$(cat "$ROOT/tests/fixtures/media-rp1-cfe.txt")"
[[ $(find_entity_node "$graph" tc358743) == /dev/v4l-subdev2 ]]
[[ $(find_entity_node "$graph" rp1-cfe-csi2_ch0) == /dev/video0 ]]
dv="$(cat "$ROOT/tests/fixtures/dv-1920x1080.txt")"
[[ $(parse_active_width "$dv") == 1920 && $(parse_active_height "$dv") == 1080 && $(parse_frame_rate "$dv") == 60.00 ]]
[[ $(classify_signal_state 0 0) == DISCONNECTED ]]
[[ $(classify_signal_state 1 0) == PRESENT_NO_SIGNAL ]]
[[ $(classify_signal_state 1 1) == LOCKED ]]
controls="$(cat "$ROOT/tests/fixtures/controls-power-present.txt")"
[[ $(parse_control_value "$controls" power_present) == 1 ]]
echo 'test-common: PASS'
