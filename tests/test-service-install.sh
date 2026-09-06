#!/usr/bin/env bash
# Test EDID boot ordering, retry behavior, and idempotent installer lifecycle.
# Usage/example: ./tests/test-service-install.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/runtime/edid" "$TMP/bin" "$TMP/root"; cp "$ROOT/tools/x1301/edid-init.sh" "$TMP/runtime/"
cat >"$TMP/runtime/validate-edid.sh" <<STUB
#!/bin/sh
echo validate >>'$TMP/calls'
STUB
cat >"$TMP/runtime/load-edid.sh" <<STUB
#!/bin/sh
n=0; [ -f '$TMP/n' ] && n=\$(cat '$TMP/n'); n=\$((n+1)); echo \$n >'$TMP/n'; echo load >>'$TMP/calls'; [ \$n -ge 3 ]
STUB
cat >"$TMP/bin/systemctl" <<STUB
#!/bin/sh
echo "\$*" >>'$TMP/systemctl'
STUB
chmod +x "$TMP/runtime/"*.sh "$TMP/bin/systemctl"
"$TMP/runtime/edid-init.sh" --retries 3 --interval 0
[[ $(grep -c validate "$TMP/calls") == 1 && $(grep -c load "$TMP/calls") == 3 ]]
grep -q '^Before=x1301-hdmi-watch.service$' "$ROOT/systemd/x1301-edid.service"
grep -q 'After=.*x1301-edid.service' "$ROOT/systemd/x1301-hdmi-watch.service"
export PATH="$TMP/bin:$PATH" X1301_INSTALL_ROOT="$TMP/root" X1301_ALLOW_NONROOT=1
"$ROOT/tools/x1301/install-service.sh" --enable --start
"$ROOT/tools/x1301/install-service.sh" --enable --restart
[[ -x "$TMP/root/usr/local/lib/x1301/hdmi-status.sh" && -L "$TMP/root/usr/local/lib/x1301/1080P60EDID.txt" ]]
[[ -f "$TMP/root/etc/systemd/system/x1301-edid.service" && -f "$TMP/root/etc/systemd/system/x1301-hdmi-watch.service" ]]
"$ROOT/tools/x1301/install-service.sh" --uninstall; [[ ! -e "$TMP/root/usr/local/lib/x1301" ]]
"$ROOT/tools/x1301/install-service.sh" --uninstall
echo 'test-service-install: PASS'
