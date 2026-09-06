#!/usr/bin/env bash
# Install/manage the watcher service. Usage: install-service.sh [--enable] [--start] [--uninstall]
# Example: sudo ./tools/x1301/install-service.sh --enable --start
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; enable=0; start=0; uninstall=0
while (($#)); do case "$1" in --enable) enable=1 ;; --start) start=1 ;; --uninstall) uninstall=1 ;; -h|--help) sed -n '2,3p' "$0"; exit 0 ;; *) echo "ERROR: unknown option: $1" >&2; exit 1 ;; esac; shift; done
[[ $EUID -eq 0 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }; command -v systemctl >/dev/null || { echo 'ERROR: systemctl not found' >&2; exit 2; }
DEST=/usr/local/lib/x1301; UNIT=/etc/systemd/system/x1301-hdmi-watch.service
if ((uninstall)); then
  ((enable || start)) && { echo 'ERROR: --uninstall cannot be combined with other options' >&2; exit 1; }
  systemctl stop x1301-hdmi-watch.service 2>/dev/null || true
  systemctl disable x1301-hdmi-watch.service 2>/dev/null || true
  rm -f "$UNIT"; rm -rf "$DEST"; systemctl daemon-reload; systemctl reset-failed x1301-hdmi-watch.service 2>/dev/null || true
  echo 'X1301 watcher service uninstalled.'; exit 0
fi
install -d -m755 "$DEST"
for script in common.sh hdmi-watch.sh configure.sh load-edid.sh runtime-status.sh; do install -m755 "$DIR/$script" "$DEST/$script"; done
install -d -m755 "$DEST/edid"; install -m644 "$DIR/edid/x1301-compatible.txt" "$DEST/edid/x1301-compatible.txt"
install -m644 "$ROOT/systemd/x1301-hdmi-watch.service" "$UNIT"; systemctl daemon-reload
((enable)) && systemctl enable x1301-hdmi-watch.service
((start)) && systemctl restart x1301-hdmi-watch.service
echo 'X1301 watcher service installed.'; ((enable)) || echo 'Service not enabled.'; ((start)) || echo 'Service not started.'
