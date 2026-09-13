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
PREFIX=${X1301_INSTALL_ROOT:-}; DEST="$PREFIX/usr/local/lib/x1301"; BIN_DIR="$PREFIX/usr/local/bin"; UNIT_DIR="$PREFIX/etc/systemd/system"
units=(x1301-edid.service x1301-hdmi-watch.service x1301-appliance-init.service x1301-appliance.service x1301-mediamtx.service x1301-stream.service x1301-web.service)
if ((uninstall)); then
  systemctl stop "${units[@]}" 2>/dev/null || true
  systemctl disable "${units[@]}" 2>/dev/null || true
  rm -f "${units[@]/#/$UNIT_DIR/}" "$BIN_DIR/x1301ctl"; rm -rf "$DEST"
  systemctl daemon-reload; systemctl reset-failed "${units[@]}" 2>/dev/null || true
  echo 'X1301 services uninstalled.'; exit 0
fi
install -d -m755 "$DEST" "$DEST/edid" "$DEST/web" "$BIN_DIR" "$UNIT_DIR" "$PREFIX/etc/x1301/profiles.d" "$PREFIX/var/lib/x1301/profiles.d" "$PREFIX/var/lib/x1301/generated"
if [[ -z $PREFIX ]]; then getent group x1301 >/dev/null || groupadd --system x1301; id x1301 >/dev/null 2>&1 || useradd --system --gid x1301 --home-dir /var/lib/x1301 --shell /usr/sbin/nologin x1301; usermod -a -G video,audio x1301; chown -R x1301:x1301 /var/lib/x1301; fi
for script in common.sh hdmi-watch.sh hdmi-status.sh runtime-status.sh configure.sh load-edid.sh validate-edid.sh edid-init.sh diagnose.sh x1301-stream.py x1301ctl x1301-appliance.py x1301-web.py; do install -m755 "$DIR/$script" "$DEST/$script"; done
install -m644 "$DIR/x1301lib.py" "$DEST/x1301lib.py"; install -m644 "$DIR/web/"* "$DEST/web/"
ln -sfn /usr/local/lib/x1301/x1301ctl "$BIN_DIR/x1301ctl"
install -m644 "$DIR/edid/x1301-compatible.txt" "$DEST/edid/x1301-compatible.txt"
ln -sfn edid/x1301-compatible.txt "$DEST/1080P60EDID.txt"
[[ -e "$PREFIX/etc/x1301/config.json" ]] || install -m644 "$ROOT/config/config.json" "$PREFIX/etc/x1301/config.json"
for unit in "${units[@]}"; do install -m644 "$ROOT/systemd/$unit" "$UNIT_DIR/$unit"; done
[[ -r "$DEST/edid/x1301-compatible.txt" ]] || { echo 'ERROR: installed EDID missing' >&2; exit 3; }
systemctl daemon-reload
((enable)) && systemctl enable "${units[@]}"
if ((start)); then systemctl restart "${units[@]}"
elif ((restart)); then systemctl restart "${units[@]}"; fi
echo 'X1301 services installed.'; ((enable)) || echo 'Services not enabled.'; ((start || restart)) || echo 'Services not started.'
