#!/usr/bin/env bash
# Explicitly install watcher service. Usage: install-service.sh [--enable]
# Example: sudo ./tools/x1301/install-service.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; enable=0
case "${1:-}" in "") ;; --enable) enable=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) exit 1;; esac
[[ $EUID -eq 0 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }; command -v systemctl >/dev/null || exit 2
sed "s|/opt/pi5-x1301-bringup|$ROOT|g" "$ROOT/systemd/x1301-hdmi-watch.service" \
  > /etc/systemd/system/x1301-hdmi-watch.service
chmod 644 /etc/systemd/system/x1301-hdmi-watch.service
systemctl daemon-reload
if ((enable)); then systemctl enable x1301-hdmi-watch.service; else echo 'Installed but not enabled. Validate hardware before using --enable.'; fi
