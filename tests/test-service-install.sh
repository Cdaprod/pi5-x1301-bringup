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
cat >"$TMP/bin/permission-probe" <<STUB
#!/bin/sh
set -eu
echo "\$1" >>'$TMP/probes'
p="\$1/.probe-\$\$"; printf test >"\$p"; mv "\$p" "\$p.moved"; rm "\$p.moved"
STUB
cat >"$TMP/bin/permission-probe-fail" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$TMP/runtime/"*.sh "$TMP/bin/"*
"$TMP/runtime/edid-init.sh" --retries 3 --interval 0
[[ $(grep -c validate "$TMP/calls") == 1 && $(grep -c load "$TMP/calls") == 3 ]]
grep -q '^Before=x1301-hdmi-watch.service$' "$ROOT/systemd/x1301-edid.service"
grep -q 'After=.*x1301-edid.service' "$ROOT/systemd/x1301-hdmi-watch.service"
export PATH="$TMP/bin:$PATH" X1301_INSTALL_ROOT="$TMP/root" X1301_ALLOW_NONROOT=1 X1301_PERMISSION_PROBE_COMMAND="$TMP/bin/permission-probe"
"$ROOT/tools/x1301/install-service.sh" --enable --start
printf 'profile' >"$TMP/root/var/lib/x1301/profiles.d/source-keep.json"
printf 'devices' >"$TMP/root/var/lib/x1301/devices.json"
printf 'ports' >"$TMP/root/var/lib/x1301/ports.json"
"$ROOT/tools/x1301/install-service.sh" --enable --restart
[[ $(cat "$TMP/root/var/lib/x1301/profiles.d/source-keep.json") == profile ]]
[[ $(cat "$TMP/root/var/lib/x1301/devices.json") == devices && $(cat "$TMP/root/var/lib/x1301/ports.json") == ports ]]
[[ $(grep -c '/profiles.d$' "$TMP/probes") -eq 2 && $(grep -c '/run/x1301/generated$' "$TMP/probes") -eq 2 ]]
[[ $(stat -c %a "$TMP/root/var/lib/x1301/profiles.d") == 755 && $(stat -c %a "$TMP/root/run/x1301/generated") == 755 ]]
[[ -x "$TMP/root/usr/local/lib/x1301/hdmi-status.sh" && -L "$TMP/root/usr/local/lib/x1301/1080P60EDID.txt" ]]
[[ -f "$TMP/root/etc/systemd/system/x1301-edid.service" && -f "$TMP/root/etc/systemd/system/x1301-hdmi-watch.service" ]]
[[ -x "$TMP/root/usr/local/lib/x1301/x1301-stream.py" && -L "$TMP/root/usr/local/bin/x1301ctl" ]]
[[ -f "$TMP/root/etc/systemd/system/x1301-appliance-init.service" && -f "$TMP/root/etc/systemd/system/x1301-mediamtx.service" ]]
grep -q '^Type=oneshot$' "$ROOT/systemd/x1301-appliance-init.service"
grep -q '^Requires=x1301-appliance-init.service$' "$ROOT/systemd/x1301-mediamtx.service"
grep -q '^StateDirectory=x1301$' "$ROOT/systemd/x1301-appliance-init.service"
grep -q '^RuntimeDirectory=x1301$' "$ROOT/systemd/x1301-appliance-init.service"
! grep -q '^StateDirectory=' "$ROOT/systemd/x1301-hdmi-watch.service"
! grep -q '^RuntimeDirectory=' "$ROOT/systemd/x1301-hdmi-watch.service"
! grep -q '^StateDirectory=' "$ROOT/systemd/x1301-appliance.service"
grep -q '^Before=x1301-hdmi-watch.service$' "$ROOT/systemd/x1301-appliance-init.service"
grep -q 'After=.*x1301-appliance-init.service' "$ROOT/systemd/x1301-hdmi-watch.service"
failure_root="$TMP/failure-root"; mkdir -p "$failure_root"
if X1301_INSTALL_ROOT="$failure_root" X1301_PERMISSION_PROBE_COMMAND="$TMP/bin/permission-probe-fail" "$ROOT/tools/x1301/install-service.sh" >"$TMP/failure.out" 2>"$TMP/failure.err"; then
  echo 'installer unexpectedly accepted failed service-user write probe' >&2; exit 1
fi
grep -q 'mutable storage verification failed' "$TMP/failure.err"
"$ROOT/tools/x1301/install-service.sh" --uninstall; [[ ! -e "$TMP/root/usr/local/lib/x1301" ]]
"$ROOT/tools/x1301/install-service.sh" --uninstall
echo 'test-service-install: PASS'
