#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
need v4l2-ctl

LOG="$LOG_DIR/capture-$(timestamp).log"
OUT="$LOG_DIR/capture-$(timestamp).raw"
exec > >(tee "$LOG") 2>&1

if [[ -n "${VIDEO:-}" ]]; then
  V="$VIDEO"
elif [[ -f "$LOG_DIR/last-video-node.txt" ]]; then
  V="$(cat "$LOG_DIR/last-video-node.txt")"
else
  echo "ERROR: no configured video node. Run configure.sh first or use VIDEO=/dev/videoN."
  exit 1
fi

section "CAPTURE"
echo "VIDEO=$V"
v4l2-ctl --verbose \
  -d "$V" \
  --set-fmt-video=width=1920,height=1080,pixelformat=RGB3 \
  --stream-mmap=4 \
  --stream-skip=3 \
  --stream-count=2 \
  --stream-to="$OUT" \
  --stream-poll

section "RESULT"
ls -lh "$OUT"
echo "CAPTURE_STATUS=SUCCESS"
echo "Raw frame file: $OUT"
echo "To preview locally on the Pi desktop:"
echo "ffplay -f rawvideo -video_size 1920x1080 -pixel_format bgr24 '$OUT'"
echo "Log: $LOG"
