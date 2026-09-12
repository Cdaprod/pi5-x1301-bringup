#!/usr/bin/env bash
# Install pinned MediaMTX fanout binary. Example: sudo install-mediamtx.sh
set -euo pipefail
version=1.21.0; archive="mediamtx_v${version}_linux_arm64.tar.gz"; sha=a8113b5928ba1a934b81557b61b8a07954b76921a4b567d54c7f086f8b39d9a2
[[ $(uname -m) == aarch64 ]] || { echo 'ERROR: pinned appliance binary requires aarch64' >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 3 -o "$tmp/$archive" "https://github.com/bluenviron/mediamtx/releases/download/v${version}/$archive"
echo "$sha  $tmp/$archive" | sha256sum -c -
tar -xzf "$tmp/$archive" -C "$tmp" mediamtx
install -m755 "$tmp/mediamtx" "${X1301_INSTALL_ROOT:-}/usr/local/bin/mediamtx"
