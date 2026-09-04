#!/usr/bin/env bash
set -o pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"

timestamp() { date +"%Y%m%d-%H%M%S"; }
section() { printf '\n========== %s ==========\n' "$*"; }
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1"
    echo "Install prerequisites: sudo apt install -y v4l-utils media-ctl ffmpeg"
    exit 1
  }
}

find_tc_subdevs() {
  local d
  for d in /dev/v4l-subdev*; do
    [[ -e "$d" ]] || continue
    if v4l2-ctl -d "$d" --all 2>&1 | grep -qiE 'tc358743|toshiba'; then
      echo "$d"
    fi
  done
}

find_tc_media() {
  local m
  for m in /dev/media*; do
    [[ -e "$m" ]] || continue
    if media-ctl -d "$m" -p 2>&1 | grep -qiE 'tc358743|csi2|rp1-cfe'; then
      echo "$m"
    fi
  done
}

find_capture_candidates() {
  local d
  for d in /dev/video*; do
    [[ -e "$d" ]] || continue
    local info
    info="$(v4l2-ctl -d "$d" --all 2>&1 || true)"
    if echo "$info" | grep -qiE 'Video Capture|Video Capture Multiplanar'; then
      echo "$d"
    fi
  done
}
