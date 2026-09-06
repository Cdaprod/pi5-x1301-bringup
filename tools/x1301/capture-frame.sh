#!/usr/bin/env bash
# Validate/configure and capture one frame. Usage/example: sudo capture-frame.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"
if ! "$DIR/capture-preflight.sh"; then "$DIR/configure.sh"; "$DIR/capture-preflight.sh"; fi
mkdir -p "$LOG_DIR/frames"; base="$LOG_DIR/frames/frame-$(timestamp)"; args=(--frames 1 --output "$base.raw")
command -v ffmpeg >/dev/null 2>&1 && args+=(--png "$base.png")
"$DIR/capture-test.sh" "${args[@]}"
