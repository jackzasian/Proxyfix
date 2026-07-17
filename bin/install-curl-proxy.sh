#!/usr/bin/env bash
# Install fixed curl-proxy.sh (treats missing *.db.sig as OK). Requires sudo.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/etc/pacman.d/curl-proxy.sh"
DST=/etc/pacman.d/curl-proxy.sh

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo bash "$0"
fi

install -m 0755 "$SRC" "$DST"
PORT=7897
if [[ -f ${SUDO_USER:+$(eval echo "~$SUDO_USER")}/.local/share/io.github.clash-verge-rev.clash-verge-rev/config.yaml ]]; then
  CFG="$(eval echo "~$SUDO_USER")/.local/share/io.github.clash-verge-rev.clash-verge-rev/config.yaml"
  PORT=$(awk '/^mixed-port:/ {print $2; exit}' "$CFG")
fi
sed -i "s|127.0.0.1:7897|127.0.0.1:${PORT}|" "$DST"
echo "Installed $DST (Clash port $PORT)"
echo "Test: /etc/pacman.d/curl-proxy.sh https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db.sig /tmp/t.sig; echo exit:\$?"
