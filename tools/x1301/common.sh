#!/usr/bin/env bash
# Shared X1301 discovery and parsing helpers.

set -o pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${X1301_LOG_DIR:-$REPO_ROOT/logs}"
DEV_ROOT="${X1301_DEV_ROOT:-/dev}"
mkdir -p "$LOG_DIR"

timestamp() { date +"%Y%m%d-%H%M%S"; }
section() { printf '\n========== %s ==========\n' "$*"; }
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    echo "Install prerequisites: sudo apt install -y v4l-utils media-ctl ffmpeg edid-decode" >&2
    return 1
  }
}

# Print the first RP1 CFE media device containing a TC358743 entity.
find_rp1_cfe_media() {
  local media graph
  for media in "$DEV_ROOT"/media*; do
    [[ -e "$media" ]] || continue
    graph="$(media-ctl -d "$media" -p 2>/dev/null || true)"
    grep -qi 'rp1-cfe' <<<"$graph" && grep -qi 'tc358743' <<<"$graph" && {
      printf '%s\n' "$media"
      return 0
    }
  done
  return 1
}

# Find a device node belonging to an entity (not merely mentioned in a link).
find_entity_node() {
  local graph="$1" entity_regex="$2"
  awk -v re="$entity_regex" '
    /^- entity / { matched = (tolower($0) ~ tolower(re)) }
    matched && /device node name/ { print $NF; exit }
  ' <<<"$graph"
}

find_tc358743_subdev() {
  local media="${1:-}" graph node
  [[ -n "$media" ]] || media="$(find_rp1_cfe_media)" || return 1
  graph="$(media-ctl -d "$media" -p 2>/dev/null)" || return 1
  node="$(find_entity_node "$graph" 'tc358743')"
  [[ -n "$node" ]] || return 1
  printf '%s\n' "$node"
}

# Extract a named v4l2 control's numeric value from --get-ctrl or --all output.
get_control_value() {
  local device="$1" control="$2" output
  output="$(v4l2-ctl -d "$device" --get-ctrl="$control" 2>/dev/null ||
            v4l2-ctl -d "$device" --all 2>/dev/null || true)"
  awk -v c="$control" '$0 ~ "^[[:space:]]*" c "[[:space:]]*:" { sub(/.*:[[:space:]]*/, ""); print $1; exit }' <<<"$output"
}

query_dv_timings() { v4l2-ctl -d "$1" --query-dv-timings 2>&1; }
parse_active_width() { awk -F: '/Active width:/ { gsub(/[^0-9]/, "", $2); print $2; exit }' <<<"$1"; }
parse_active_height() { awk -F: '/Active height:/ { gsub(/[^0-9]/, "", $2); print $2; exit }' <<<"$1"; }

find_capture_candidates() {
  local d info
  for d in "$DEV_ROOT"/video*; do
    [[ -e "$d" ]] || continue
    info="$(v4l2-ctl -d "$d" --all 2>&1 || true)"
    grep -qiE 'Video Capture|Video Capture Multiplanar' <<<"$info" && printf '%s\n' "$d"
  done
}
