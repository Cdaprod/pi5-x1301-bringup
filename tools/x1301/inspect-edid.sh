#!/usr/bin/env bash
# Decode an EDID file without changing hardware.
# Usage: ./tools/x1301/inspect-edid.sh [EDID_FILE]
# Example: ./tools/x1301/inspect-edid.sh tools/x1301/edid/x1301-compatible.txt
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
need edid-decode
EDID="${1:-$DIR/edid/x1301-compatible.txt}"
[[ -r "$EDID" ]] || { echo "ERROR: EDID not readable: $EDID" >&2; exit 2; }
edid-decode "$EDID"
