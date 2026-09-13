#!/usr/bin/env bash
# Verify X1301 service-user storage access. Example: sudo verify-permissions.sh
set -euo pipefail
quiet=0
while (($#)); do case "$1" in --quiet) quiet=1;; -h|--help) sed -n '2,2p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 2;; esac; shift; done
user=${X1301_SERVICE_USER:-x1301}
prefix=${X1301_INSTALL_ROOT:-}
directories=("$prefix/var/lib/x1301" "$prefix/var/lib/x1301/profiles.d" "$prefix/var/lib/x1301/generated" "$prefix/run/x1301" "$prefix/run/x1301/generated")

probe_directory() {
  local directory=$1
  if [[ -n ${X1301_PERMISSION_PROBE_COMMAND:-} ]]; then
    "$X1301_PERMISSION_PROBE_COMMAND" "$directory"
  else
    runuser -u "$user" -- sh -c '
      set -eu
      directory=$1
      path="$directory/.x1301-write-test-$$"
      trap '\''rm -f "$path" "$path.moved"'\'' EXIT HUP INT TERM
      printf test >"$path"
      mv "$path" "$path.moved"
      rm "$path.moved"
      trap - EXIT HUP INT TERM
    ' sh "$directory"
  fi
}

if [[ -z ${X1301_PERMISSION_PROBE_COMMAND:-} ]]; then
  id "$user" 2>/dev/null || { echo "ERROR: X1301 service user does not exist: $user" >&2; exit 3; }
  ((quiet)) || { printf 'service_identity: '; id "$user"; }
else
  ((quiet)) || echo "service_identity: $user (external test probe)"
fi
for directory in "${directories[@]}"; do
  [[ -d $directory ]] || { echo "ERROR: required X1301 directory is missing: $directory" >&2; exit 4; }
  ((quiet)) || stat -c 'directory: %a %U:%G %n' "$directory"
  if ! probe_directory "$directory"; then
    echo "ERROR: service user $user cannot create, rename, and delete files in $directory" >&2
    ((quiet)) || {
      findmnt -T "$directory" -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
      getfacl -p "$directory" 2>/dev/null || true
      lsattr -d "$directory" 2>/dev/null || true
    }
    exit 5
  fi
  ((quiet)) || echo "write_test: PASS $directory"
done
