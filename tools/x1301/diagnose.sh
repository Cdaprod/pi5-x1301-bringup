#!/usr/bin/env bash
set -uo pipefail

echo "========== SYSTEM =========="
uname -a

echo
echo "========== SERVICES =========="
systemctl is-enabled x1301-edid.service 2>/dev/null || true
systemctl is-active x1301-edid.service 2>/dev/null || true
systemctl is-enabled x1301-hdmi-watch.service 2>/dev/null || true
systemctl is-active x1301-hdmi-watch.service 2>/dev/null || true

echo
echo "========== RUNTIME STATE =========="
cat /run/x1301/state.env 2>/dev/null || echo "No /run/x1301/state.env"

echo
echo "========== MEDIA DEVICES =========="
ls -l /dev/media* /dev/video* /dev/v4l-subdev* 2>/dev/null || true

STATE=/run/x1301/state.env

MEDIA=""
SUBDEV=""
VIDEO=""

if [[ -r "$STATE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE"
    MEDIA="${X1301_MEDIA:-}"
    SUBDEV="${X1301_SUBDEV:-}"
    VIDEO="${X1301_VIDEO:-}"
fi

echo
echo "========== DV TIMINGS =========="
if [[ -n "$SUBDEV" && -e "$SUBDEV" ]]; then
    v4l2-ctl -d "$SUBDEV" --query-dv-timings 2>&1 || true
else
    echo "No published TC358743 subdevice"
fi

echo
echo "========== VIDEO FORMAT =========="
if [[ -n "$VIDEO" && -e "$VIDEO" ]]; then
    v4l2-ctl -d "$VIDEO" --get-fmt-video 2>&1 || true
else
    echo "No published capture node"
fi

echo
echo "========== MEDIA GRAPH =========="
if [[ -n "$MEDIA" && -e "$MEDIA" ]]; then
    media-ctl -d "$MEDIA" -p 2>&1 || true
else
    echo "No published media device"
fi

echo
echo "========== WATCHER JOURNAL =========="
journalctl \
    -u x1301-hdmi-watch.service \
    -b \
    --no-pager \
    -n 120 \
    2>&1 || true

echo
echo "========== RP1-CFE / TC358743 KERNEL LOG =========="
dmesg 2>/dev/null |
    grep -Ei 'rp1-cfe|tc358743|csi|stream|pipeline|format mismatch' |
    tail -n 120 || true