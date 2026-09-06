#!/usr/bin/env bash
# Test hot-plug, timing identity, node changes, retries, and atomic state without hardware.
# Usage/example: ./tests/test-watcher-service.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dev" "$TMP/log"; touch "$TMP/dev/media3"
cat >"$TMP/bin/media-ctl" <<STUB
#!/bin/sh
state=\$(sed -n "\$(cat '$TMP/count'){p;q}" '$TMP/states')
video=video0; [ "\$state" = locked1080p30new ] && video=video12
cat '$ROOT/tests/fixtures/media-rp1-cfe.txt' | sed -e 's|/dev/|$TMP/dev/|g' -e "s/video0/\$video/"
STUB
cat >"$TMP/bin/v4l2-ctl" <<STUB
#!/bin/sh
state=\$(sed -n "\$(cat '$TMP/count'){p;q}" '$TMP/states')
case "\$*" in
 *power_present*) [ "\$state" = disconnected ] && echo 'power_present: 0' || echo 'power_present: 1';;
 *audio_present*) echo 'audio_present: 1';;
 *audio_sampling_rate*) echo 'audio_sampling_rate: 48000';;
 *query-dv-timings*) echo \$((\$(cat '$TMP/count') + 1)) >'$TMP/count'; case "\$state" in
   locked1080) cat '$ROOT/tests/fixtures/dv-1920x1080.txt';;
   locked720) cat '$ROOT/tests/fixtures/dv-1280x720.txt';;
   locked1080p30new) cat '$ROOT/tests/fixtures/dv-1920x1080-30.txt';;
   *) exit 1;; esac;;
esac
STUB
cat >"$TMP/configure" <<STUB
#!/bin/sh
n=0; [ -f '$TMP/configure-count' ] && n=\$(cat '$TMP/configure-count'); n=\$((n+1)); echo \$n >'$TMP/configure-count'
[ \$n -ne 1 ]
STUB
chmod +x "$TMP/bin/"* "$TMP/configure"
printf '%s\n' disconnected present locked1080 locked1080 locked720 disconnected locked1080p30new locked1080p30new >"$TMP/states"; echo 1 >"$TMP/count"
export PATH="$TMP/bin:$PATH" X1301_DEV_ROOT="$TMP/dev" X1301_LOG_DIR="$TMP/log" X1301_RUNTIME_STATE="$TMP/state.env" X1301_CONFIGURE_COMMAND="$TMP/configure" X1301_CONFIGURE_BACKOFF=0 HDMI_WATCH_MAX_POLLS=8
"$ROOT/tools/x1301/hdmi-watch.sh" --configure --interval 0 >"$TMP/events" 2>"$TMP/errors"
[[ $(cat "$TMP/configure-count") == 4 ]]
[[ $(grep -c 'X1301 EVENT MODE_CHANGE' "$TMP/events") == 3 ]]
grep -q 'CONFIGURE FAILED' "$TMP/errors"; grep -q "X1301_SIGNAL_STATE='LOCKED'" "$TMP/state.env"; grep -q "X1301_CONFIGURED='1'" "$TMP/state.env"
grep -q "X1301_VIDEO='$TMP/dev/video12'" "$TMP/state.env"; grep -q "X1301_FPS='30.00'" "$TMP/state.env"; grep -q "X1301_PIXELCLOCK_HZ='74250000'" "$TMP/state.env"
grep -q "X1301_MODE_GENERATION='3'" "$TMP/state.env"; ! compgen -G "$TMP/state.env.tmp.*" >/dev/null
"$ROOT/tools/x1301/runtime-status.sh" --json >"$TMP/runtime.json"; python3 -m json.tool "$TMP/runtime.json" >/dev/null
grep -q '"signal_state": "LOCKED"' "$TMP/runtime.json"; grep -q '"configured": true' "$TMP/runtime.json"; grep -q '"mode_generation": 3' "$TMP/runtime.json"
echo 'test-watcher-service: PASS'
