#!/usr/bin/env bash
# Hardware-free JSON/status exit tests. Usage/example: ./tests/test-status-parser.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dev" "$TMP/log"; touch "$TMP/dev/media3"
cat >"$TMP/bin/media-ctl" <<STUB
#!/bin/sh
cat '$ROOT/tests/fixtures/media-rp1-cfe.txt' | sed 's|/dev/|$TMP/dev/|g'
STUB
cat >"$TMP/bin/v4l2-ctl" <<STUB
#!/bin/sh
case "\$*" in
  *power_present*) [ "\${STATUS_CASE:-present}" = disconnected ] && echo 'power_present: 0' || echo 'power_present: 1';;
  *audio_present*) echo 'audio_present: 0';;
  *audio_sampling_rate*) echo 'audio_sampling_rate: 0';;
  *query-dv-timings*) [ "\${STATUS_CASE:-present}" = locked ] && cat '$ROOT/tests/fixtures/dv-1920x1080.txt' || { cat '$ROOT/tests/fixtures/dv-no-link.txt' >&2; exit 1; };;
esac
STUB
chmod +x "$TMP/bin/"*; export PATH="$TMP/bin:$PATH" X1301_DEV_ROOT="$TMP/dev" X1301_LOG_DIR="$TMP/log"

for state in present disconnected locked; do
  STATUS_CASE=$state "$ROOT/tools/x1301/hdmi-status.sh" --json >"$TMP/$state.json"
  python3 -m json.tool "$TMP/$state.json" >/dev/null
  ! grep -Eq '"[^" ]+":.*"[^" ]+":' "$TMP/$state.json"
done
grep -q '"signal_state": "PRESENT_NO_SIGNAL"' "$TMP/present.json"
grep -q '"signal_state": "DISCONNECTED"' "$TMP/disconnected.json"
grep -q '"signal_state": "LOCKED"' "$TMP/locked.json"
grep -q '"width": 1920' "$TMP/locked.json"

rm "$TMP/dev/media3"
set +e; "$ROOT/tools/x1301/hdmi-status.sh" --json >"$TMP/error.json" 2>/dev/null; rc=$?; set -e
[[ $rc -ne 0 ]]; python3 -m json.tool "$TMP/error.json" >/dev/null; grep -q '"signal_state": "ERROR"' "$TMP/error.json"
echo 'test-status-parser: PASS'
