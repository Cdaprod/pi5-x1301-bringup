#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
need v4l2-ctl

MODE_FILE="$LOG_DIR/last-mode.env"
[[ -r "$MODE_FILE" ]] || { echo "ERROR: run configure.sh first; $MODE_FILE is missing" >&2; exit 2; }
# shellcheck disable=SC1090
source "$MODE_FILE"

LOG="$LOG_DIR/capture-$(timestamp).log"
OUT="$LOG_DIR/capture-$(timestamp).raw"
exec > >(tee "$LOG") 2>&1

V="${VIDEO:-$X1301_VIDEO}"
WIDTH="${X1301_WIDTH:?missing width in last-mode.env}"
HEIGHT="${X1301_HEIGHT:?missing height in last-mode.env}"

section "CAPTURE"
echo "VIDEO=$V"
v4l2-ctl --verbose \
  -d "$V" \
  --set-fmt-video=width="$WIDTH",height="$HEIGHT",pixelformat="${X1301_PIXELFORMAT:-RGB3}" \
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
echo "ffplay -f rawvideo -video_size ${WIDTH}x${HEIGHT} -pixel_format bgr24 '$OUT'"
echo "Log: $LOG"
