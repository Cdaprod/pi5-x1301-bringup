#!/usr/bin/env bash
# Validate and load the bundled EDID after bounded device discovery. Usage: edid-init.sh [--retries N] [--interval SEC]
# Example: sudo ./tools/x1301/edid-init.sh --retries 30 --interval 1
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; retries="${X1301_EDID_RETRIES:-30}"; interval="${X1301_EDID_RETRY_INTERVAL:-1}"
while (($#)); do case "$1" in --retries) retries=${2:?}; shift;; --interval) interval=${2:?}; shift;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
[[ $retries =~ ^[1-9][0-9]*$ && $interval =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'ERROR: invalid retry settings' >&2; exit 1; }
"$DIR/validate-edid.sh" >/dev/null
for ((attempt=1; attempt<=retries; attempt++)); do
  if "$DIR/load-edid.sh"; then exit 0; fi
  ((attempt < retries)) && sleep "$interval"
done
echo "ERROR: X1301 EDID initialization failed after $retries attempts" >&2; exit 3
