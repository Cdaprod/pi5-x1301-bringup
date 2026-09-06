#!/usr/bin/env bash
# Validate an EDID without hardware. Usage: validate-edid.sh [--file PATH]
# Example: ./tools/x1301/validate-edid.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; file="$DIR/edid/x1301-compatible.txt"
while (($#)); do case "$1" in --file) (($# >= 2)) || exit 1; file=$2; shift;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) echo "ERROR: unknown option: $1" >&2; exit 1;; esac; shift; done
[[ -r "$file" ]] || { echo "ERROR: EDID not found: $file" >&2; exit 2; }
hex="$(tr -d '[:space:]' <"$file")"
[[ $hex =~ ^[[:xdigit:]]+$ && $(( ${#hex} % 256 )) -eq 0 && ${hex,,} == 00ffffffffffff00* ]] || { echo 'EDID_VALID=0'; echo 'ERROR: invalid EDID hex/header/block length' >&2; exit 3; }
for ((block=0; block<${#hex}; block+=256)); do
  sum=0
  for ((offset=block; offset<block+256; offset+=2)); do sum=$((sum + 16#${hex:offset:2})); done
  ((sum % 256 == 0)) || { echo 'EDID_VALID=0'; echo "ERROR: checksum failure in block $((block / 256))" >&2; exit 4; }
done
if command -v edid-decode >/dev/null 2>&1; then
  output="$(edid-decode "$file" 2>&1)" || { echo "$output"; echo 'EDID_VALID=0'; exit 4; }
  echo "$output"
  grep -qi 'checksum.*fail\|checksum.*invalid' <<<"$output" && { echo 'EDID_VALID=0'; exit 4; }
else echo 'WARNING: edid-decode unavailable; structural checks only' >&2; fi
echo 'EDID_VALID=1'
