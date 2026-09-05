#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

need v4l2-ctl
need media-ctl

[[ $EUID -eq 0 ]] || {
  echo "Run with sudo."
  exit 1
}

LOG="$LOG_DIR/configure-$(timestamp).log"
exec > >(tee "$LOG") 2>&1

section "DISCOVERY"

# Find the actual TC358743 V4L2 subdevice.
SUBDEV=""
for d in /dev/v4l-subdev*; do
  [[ -e "$d" ]] || continue

  info="$(v4l2-ctl -d "$d" --all 2>&1 || true)"

  if grep -qi 'tc358743' <<<"$info"; then
    SUBDEV="$d"
    break
  fi
done

if [[ -z "$SUBDEV" ]]; then
  echo "ERROR: TC358743 V4L2 subdevice not found."
  exit 2
fi

echo "SUBDEV=$SUBDEV"

mapfile -t MEDIAS < <(find_tc_media)

MEDIA=""
for m in "${MEDIAS[@]}"; do
  graph="$(media-ctl -d "$m" -p 2>&1 || true)"

  if grep -qi 'tc358743' <<<"$graph" &&
     grep -qi 'csi2' <<<"$graph" &&
     grep -qi 'rp1-cfe' <<<"$graph"; then
    MEDIA="$m"
    break
  fi
done

if [[ -z "$MEDIA" ]]; then
  echo "ERROR: could not identify RP1 CFE media graph."
  printf 'Candidates: %s\n' "${MEDIAS[*]:-none}"
  exit 3
fi

echo "MEDIA=$MEDIA"

section "LOAD EDID"

EDID="$REPO_ROOT/tools/x1301/1080P60EDID.txt"

v4l2-ctl \
  -d "$SUBDEV" \
  --set-edid=file="$EDID" \
  --fix-edid-checksums

section "WAIT FOR HDMI"

TIMINGS_OK=0

for attempt in {1..15}; do
  echo "Waiting for HDMI timings... attempt $attempt/15"

  if v4l2-ctl -d "$SUBDEV" --query-dv-timings; then
    TIMINGS_OK=1
    break
  fi

  sleep 1
done

if [[ "$TIMINGS_OK" -ne 1 ]]; then
  echo "ERROR: HDMI did not establish valid DV timings."
  echo "Check that the HDMI source is powered and actively outputting video."
  exit 4
fi

section "APPLY HDMI TIMINGS"

v4l2-ctl \
  -d "$SUBDEV" \
  --set-dv-bt-timings query

section "RESET MEDIA GRAPH"

media-ctl -d "$MEDIA" -r

section "ENABLE CSI2 -> CFE LINK"

if ! media-ctl \
  -d "$MEDIA" \
  -l "'csi2':4 -> 'rp1-cfe-csi2_ch0':0 [1]"; then

  echo "ERROR: expected RP1 CFE entity names were not found."
  media-ctl -d "$MEDIA" -p || true
  exit 5
fi

section "CONFIGURE RGB888 1080P"

media-ctl \
  -d "$MEDIA" \
  -V "'csi2':0 [fmt:RGB888_1X24/1920x1080 field:none colorspace:srgb]"

media-ctl \
  -d "$MEDIA" \
  -V "'csi2':4 [fmt:RGB888_1X24/1920x1080 field:none colorspace:srgb]"

section "FINAL GRAPH"

media-ctl -d "$MEDIA" -p

section "CAPTURE CANDIDATES"

mapfile -t VIDEOS < <(find_capture_candidates)
printf '%s\n' "${VIDEOS[@]:-}"

VIDEO=""

for v in "${VIDEOS[@]}"; do
  if v4l2-ctl \
    -d "$v" \
    --set-fmt-video=width=1920,height=1080,pixelformat=RGB3 \
    >/dev/null 2>&1; then

    fmt="$(v4l2-ctl -d "$v" --get-fmt-video 2>&1 || true)"

    if grep -q "RGB3" <<<"$fmt"; then
      VIDEO="$v"
      break
    fi
  fi
done

if [[ -z "$VIDEO" ]]; then
  echo "ERROR: no capture candidate accepted 1920x1080 RGB3."
  exit 6
fi

section "RESULT"

echo "X1301_STATUS=CONFIGURED"
echo "SUBDEV=$SUBDEV"
echo "MEDIA=$MEDIA"
echo "VIDEO=$VIDEO"

echo "$VIDEO" > "$LOG_DIR/last-video-node.txt"

echo "Log: $LOG"