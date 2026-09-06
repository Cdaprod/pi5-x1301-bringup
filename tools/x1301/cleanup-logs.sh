#!/usr/bin/env bash
# Remove old known X1301 logs. Usage: cleanup-logs.sh [--keep N] [--dry-run]
# Example: ./tools/x1301/cleanup-logs.sh --keep 20 --dry-run
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/common.sh"; keep=20; dry=0
while (($#)); do case "$1" in --keep) keep=${2:?}; shift;; --dry-run) dry=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) exit 1;; esac; shift; done
[[ $keep =~ ^[0-9]+$ ]] || { echo 'ERROR: --keep must be nonnegative' >&2; exit 1; }
[[ $LOG_DIR == "$REPO_ROOT/logs" ]] || { echo 'ERROR: cleanup is restricted to repository logs' >&2; exit 2; }
for pattern in 'inventory-*.log' 'configure-*.log' 'status-*.log' 'capture-*.raw' 'frame-*.raw' 'frame-*.png'; do
  mapfile -t files < <(find "$LOG_DIR" -type f -name "$pattern" -printf '%T@ %p\n' | sort -rn | tail -n "+$((keep+1))" | cut -d' ' -f2-)
  for file in "${files[@]}"; do ((dry)) && printf 'WOULD_DELETE=%s\n' "$file" || { rm -- "$file"; printf 'DELETED=%s\n' "$file"; }; done
done
