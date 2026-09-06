#!/usr/bin/env bash
# Load an EDID explicitly. Usage: load-edid.sh [--file PATH]
# Example: sudo ./tools/x1301/load-edid.sh --file tools/x1301/edid/x1301-compatible.txt
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
EDID="$DIR/edid/x1301-compatible.txt"
while (($#)); do case "$1" in --file) (($# >= 2)) || { echo 'ERROR: --file needs a path' >&2; exit 1; }; EDID=$2; shift;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
[[ -r "$EDID" ]] || { echo "ERROR: EDID not readable: $EDID" >&2; exit 2; }
need media-ctl; need v4l2-ctl
[[ $EUID -eq 0 || ${X1301_ALLOW_NONROOT:-0} == 1 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }
MEDIA="$(find_rp1_cfe_media)" || { echo 'ERROR: owning media device not found' >&2; exit 3; }
SUBDEV="$(find_tc358743_subdev "$MEDIA")" || { echo 'ERROR: TC358743 entity not found' >&2; exit 3; }
output="$(v4l2-ctl -d "$SUBDEV" --set-edid="file=$EDID" --fix-edid-checksums 2>&1)" || { echo "$output" >&2; echo 'ERROR: VIDIOC_S_EDID failed' >&2; exit 4; }
printf 'EDID_STATUS=LOADED\nMEDIA=%s\nSUBDEV=%s\nPOWER_PRESENT=%s\n' "$MEDIA" "$SUBDEV" "$(get_control_value "$SUBDEV" power_present)"
