#!/usr/bin/env bash
# Load the compatible multi-mode EDID; timing lock is not required.
# Usage: sudo ./tools/x1301/load-edid.sh [EDID_FILE]
# Example: sudo ./tools/x1301/load-edid.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
need media-ctl; need v4l2-ctl
[[ $EUID -eq 0 || ${X1301_ALLOW_NONROOT:-0} == 1 ]] || { echo "ERROR: run with sudo" >&2; exit 1; }
EDID="${1:-$DIR/edid/x1301-compatible.txt}"
[[ -r "$EDID" ]] || { echo "ERROR: EDID not readable: $EDID" >&2; exit 2; }
MEDIA="$(find_rp1_cfe_media)" || { echo "ERROR: owning RP1 CFE media device not found" >&2; exit 3; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo "ERROR: TC358743 subdevice not found in $MEDIA" >&2; exit 3; }
if ! output="$(v4l2-ctl -d "$SUBDEV" --set-edid="file=$EDID" --fix-edid-checksums 2>&1)"; then
  echo "$output" >&2; echo "ERROR: VIDIOC_S_EDID failed" >&2; exit 4
fi
power="$(get_control_value "$SUBDEV" power_present)"; power="${power:-unknown}"
printf 'EDID_STATUS=LOADED\nMEDIA=%s\nSUBDEV=%s\npower_present=%s\n' "$MEDIA" "$SUBDEV" "$power"
