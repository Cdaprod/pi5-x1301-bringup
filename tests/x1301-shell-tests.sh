#!/usr/bin/env bash
# Isolated tests for X1301 discovery, parsing, status, and transitions.
# Usage/example: ./tests/x1301-shell-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dev" "$TMP/log"; touch "$TMP/dev/media0" "$TMP/dev/media1"
cat >"$TMP/bin/media-ctl" <<'STUB'
#!/usr/bin/env bash
dev=; while (($#)); do [[ $1 == -d ]] && { dev=$2; shift 2; continue; }; shift; done
[[ $dev == */media0 ]] && { echo '- entity 1: unrelated (1 pad, 0 link)'; exit; }
cat <<GRAPH
- entity 1: rp1-cfe-csi2_ch0 (1 pad, 1 link)
    device node name $X1301_DEV_ROOT/video7
- entity 2: csi2 (5 pads, 2 links)
    device node name $X1301_DEV_ROOT/v4l-subdev8
    -> "tc358743 10-000f":0
- entity 3: tc358743 10-000f (1 pad, 1 link)
    device node name $X1301_DEV_ROOT/v4l-subdev9
GRAPH
STUB
cat >"$TMP/bin/v4l2-ctl" <<'STUB'
#!/usr/bin/env bash
args="$*"
if [[ $args == *--get-ctrl=power_present* ]]; then
  state=${V4_STATE:-locked}; [[ -n ${V4_SEQUENCE_FILE:-} ]] && state=$(sed -n "$(cat "$V4_SEQUENCE_FILE"){p;q}" "$V4_STATES")
  [[ $state == disconnected ]] && echo 'power_present: 0' || echo 'power_present: 1'; exit
fi
[[ $args == *--get-ctrl=audio_sampling_rate* ]] && { echo 'audio_sampling_rate: 48000'; exit; }
[[ $args == *--get-ctrl=audio_present* ]] && { echo 'audio_present: 1'; exit; }
if [[ $args == *--query-dv-timings* ]]; then
  state=${V4_STATE:-locked}
  if [[ -n ${V4_SEQUENCE_FILE:-} ]]; then n=$(cat "$V4_SEQUENCE_FILE"); state=$(sed -n "${n}{p;q}" "$V4_STATES"); echo $((n+1)) >"$V4_SEQUENCE_FILE"; fi
  [[ $state == locked720 ]] && { printf 'Active width: 1280\nActive height: 720\nPixelclock: 74250000 Hz (60.00 frames per second)\n'; exit; }
  [[ $state == locked1080 || $state == locked ]] && { printf 'Active width: 1920\nActive height: 1080\nPixelclock: 148500000 Hz (59.94 frames per second)\n'; exit; }
  echo 'VIDIOC_QUERY_DV_TIMINGS: failed: Link has been severed' >&2; exit 1
fi
exit 0
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" X1301_DEV_ROOT="$TMP/dev" X1301_LOG_DIR="$TMP/log"
source "$ROOT/tools/x1301/common.sh"
[[ $(find_rp1_cfe_media) == "$TMP/dev/media1" ]]
[[ $(find_tc358743_subdev "$TMP/dev/media1") == "$TMP/dev/v4l-subdev9" ]]
[[ $(find_rp1_cfe_capture_node "$TMP/dev/media1") == "$TMP/dev/video7" ]]
sample=$'Active width: 1366 pixels\nActive height: 768 lines'
[[ $(parse_active_width "$sample") == 1366 && $(parse_active_height "$sample") == 768 ]]
V4_STATE=locked1080 "$ROOT/tools/x1301/hdmi-status.sh" >"$TMP/status"
grep -qx "VIDEO=$TMP/dev/video7" "$TMP/status"; grep -qx 'SIGNAL=LOCKED' "$TMP/status"; grep -qx 'ACTIVE_WIDTH=1920' "$TMP/status"; grep -qx 'FPS=59.94' "$TMP/status"
set +e; V4_STATE=no_signal "$ROOT/tools/x1301/hdmi-status.sh" >"$TMP/status2"; rc=$?; set -e
[[ $rc == 3 ]]; grep -qx 'POWER_PRESENT=1' "$TMP/status2"; grep -qx 'SIGNAL=PRESENT_NO_SIGNAL' "$TMP/status2"; grep -qx 'DV_TIMINGS=NO_LINK' "$TMP/status2"; grep -qx 'STATE=NO_SIGNAL' "$TMP/status2"
set +e; V4_STATE=disconnected "$ROOT/tools/x1301/hdmi-status.sh" >"$TMP/status3"; rc=$?; set -e
[[ $rc == 3 ]]; grep -qx 'POWER_PRESENT=0' "$TMP/status3"; grep -qx 'SIGNAL=DISCONNECTED' "$TMP/status3"
printf '%s\n' disconnected no_signal locked1080 locked1080 locked720 >"$TMP/states"; echo 1 >"$TMP/count"
V4_STATES="$TMP/states" V4_SEQUENCE_FILE="$TMP/count" HDMI_WATCH_MAX_POLLS=5 "$ROOT/tools/x1301/hdmi-watch.sh" >"$TMP/watch"
diff -u <(printf 'DISCONNECTED\nPRESENT_NO_SIGNAL\nLOCKED 1920x1080\nMODE_CHANGE 1280x720\n') "$TMP/watch"
echo 'x1301 shell tests: PASS'
