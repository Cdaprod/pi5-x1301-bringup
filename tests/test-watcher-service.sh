#!/usr/bin/env bash
# Test watcher transitions/configuration/state atomically without hardware. Usage/example: test-watcher-service.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dev" "$TMP/log"; touch "$TMP/dev/media3"
cat >"$TMP/bin/media-ctl" <<STUB
#!/bin/sh
cat '$ROOT/tests/fixtures/media-rp1-cfe.txt' | sed 's|/dev/|$TMP/dev/|g'
STUB
cat >"$TMP/bin/v4l2-ctl" <<STUB
#!/bin/sh
state=\$(sed -n "\$(cat '$TMP/count'){p;q}" '$TMP/states')
case "\$*" in *power_present*) [ "\$state" = disconnected ] && echo 'power_present: 0' || echo 'power_present: 1';; *query-dv-timings*) echo \$((\$(cat '$TMP/count') + 1)) >'$TMP/count'; case "\$state" in locked1080) cat '$ROOT/tests/fixtures/dv-1920x1080.txt';; locked720) printf 'Active width: 1280\nActive height: 720\nPixelclock: 74250000 Hz (60.00 frames per second)\n';; *) exit 1;; esac;; esac
STUB
cat >"$TMP/configure" <<STUB
#!/bin/sh
echo configure >>'$TMP/configures'
STUB
chmod +x "$TMP/bin/"* "$TMP/configure"
printf '%s\n' disconnected present locked1080 locked1080 locked720 disconnected >"$TMP/states"; echo 1 >"$TMP/count"
export PATH="$TMP/bin:$PATH" X1301_DEV_ROOT="$TMP/dev" X1301_LOG_DIR="$TMP/log" X1301_RUNTIME_STATE="$TMP/state.env" X1301_CONFIGURE_COMMAND="$TMP/configure" HDMI_WATCH_MAX_POLLS=6
"$ROOT/tools/x1301/hdmi-watch.sh" --configure --interval 0 >"$TMP/events"
[[ $(wc -l <"$TMP/configures") == 2 ]]
[[ $(grep -c 'X1301 EVENT LOCKED' "$TMP/events") == 1 ]]; [[ $(grep -c 'X1301 EVENT MODE_CHANGE' "$TMP/events") == 1 ]]
grep -q "X1301_SIGNAL_STATE='DISCONNECTED'" "$TMP/state.env"; grep -q "X1301_CONFIGURED='0'" "$TMP/state.env"
! compgen -G "$TMP/state.env.tmp.*" >/dev/null
"$ROOT/tools/x1301/runtime-status.sh" --json >"$TMP/runtime.json"; python3 -m json.tool "$TMP/runtime.json" >/dev/null
grep -q '"signal_state": "DISCONNECTED"' "$TMP/runtime.json"; grep -q '"configured": false' "$TMP/runtime.json"
echo 'test-watcher-service: PASS'
