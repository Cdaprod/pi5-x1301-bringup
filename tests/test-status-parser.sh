#!/usr/bin/env bash
# Hardware-free JSON/status tests. Usage/example: ./tests/test-status-parser.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dev" "$TMP/log"; touch "$TMP/dev/media3"
cat >"$TMP/bin/media-ctl" <<STUB
#!/bin/sh
cat '$ROOT/tests/fixtures/media-rp1-cfe.txt' | sed 's|/dev/|$TMP/dev/|g'
STUB
cat >"$TMP/bin/v4l2-ctl" <<STUB
#!/bin/sh
case "\$*" in *power_present*) echo 'power_present: 1';; *audio_present*) echo 'audio_present: 0';; *audio_sampling_rate*) echo 'audio_sampling_rate: 0';; *query-dv-timings*) cat '$ROOT/tests/fixtures/dv-no-link.txt' >&2; exit 1;; esac
STUB
chmod +x "$TMP/bin/"*; export PATH="$TMP/bin:$PATH" X1301_DEV_ROOT="$TMP/dev" X1301_LOG_DIR="$TMP/log"
set +e; "$ROOT/tools/x1301/hdmi-status.sh" --json >"$TMP/status.json"; rc=$?; set -e
[[ $rc == 3 ]]; python3 -m json.tool "$TMP/status.json" >/dev/null
grep -q '"X1301_STATUS_SCHEMA": 1' "$TMP/status.json"; grep -q '"signal_state": "PRESENT_NO_SIGNAL"' "$TMP/status.json"; grep -q '"width": null' "$TMP/status.json"
echo 'test-status-parser: PASS'
