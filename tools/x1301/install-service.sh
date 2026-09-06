#!/usr/bin/env bash
# Install/manage X1301 EDID and watcher services. Usage: install-service.sh [--enable] [--start|--restart] [--uninstall]
# Example: sudo ./tools/x1301/install-service.sh --enable --start
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; enable=0; start=0; restart=0; uninstall=0
while (($#)); do case "$1" in --enable) enable=1;; --start) start=1;; --restart) restart=1;; --uninstall) uninstall=1;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
((start && restart)) && { echo 'ERROR: --start and --restart are mutually exclusive' >&2; exit 1; }
((uninstall && (enable || start || restart))) && { echo 'ERROR: --uninstall cannot be combined with lifecycle options' >&2; exit 1; }
[[ $EUID -eq 0 || ${X1301_ALLOW_NONROOT:-0} == 1 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }
command -v systemctl >/dev/null || { echo 'ERROR: systemctl not found' >&2; exit 2; }
PREFIX=${X1301_INSTALL_ROOT:-}; DEST="$PREFIX/usr/local/lib/x1301"; UNIT_DIR="$PREFIX/etc/systemd/system"
units=(x1301-edid.service x1301-hdmi-watch.service)
if ((uninstall)); then
  systemctl stop x1301-hdmi-watch.service x1301-edid.service 2>/dev/null || true
  systemctl disable x1301-hdmi-watch.service x1301-edid.service 2>/dev/null || true
  rm -f "$UNIT_DIR/x1301-hdmi-watch.service" "$UNIT_DIR/x1301-edid.service"; rm -rf "$DEST"
  systemctl daemon-reload; systemctl reset-failed "${units[@]}" 2>/dev/null || true
  echo 'X1301 services uninstalled.'; exit 0
fi
install -d -m755 "$DEST" "$DEST/edid" "$UNIT_DIR"
for script in common.sh hdmi-watch.sh hdmi-status.sh runtime-status.sh configure.sh load-edid.sh validate-edid.sh edid-init.sh; do install -m755 "$DIR/$script" "$DEST/$script"; done
install -m644 "$DIR/edid/x1301-compatible.txt" "$DEST/edid/x1301-compatible.txt"
ln -sfn edid/x1301-compatible.txt "$DEST/1080P60EDID.txt"
for unit in "${units[@]}"; do install -m644 "$ROOT/systemd/$unit" "$UNIT_DIR/$unit"; done
systemctl daemon-reload
((enable)) && systemctl enable x1301-edid.service x1301-hdmi-watch.service
if ((start)); then systemctl restart x1301-edid.service x1301-hdmi-watch.service
elif ((restart)); then systemctl restart x1301-edid.service x1301-hdmi-watch.service; fi
echo 'X1301 services installed.'; ((enable)) || echo 'Services not enabled.'; ((start || restart)) || echo 'Services not started.'
