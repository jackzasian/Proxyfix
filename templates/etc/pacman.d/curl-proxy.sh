#!/bin/bash
# Pacman XferCommand wrapper — route every download through Clash mixed port.
set -euo pipefail

PROXY="${PACMAN_PROXY_URL:-http://127.0.0.1:7897}"
URL=$1
OUT=$2

# geo.mirror.pkgbuild.com and pkgs.omarchy.org omit optional repo *.db.sig / *.files.sig.
# pacman.conf uses DatabaseOptional — missing repo signatures are OK.
if [[ $URL == *.db.sig || $URL == *.files.sig ]]; then
  code=$(/usr/bin/curl \
    --proxy "$PROXY" \
    --connect-timeout 20 \
    --retry 1 \
    --http1.1 \
    -sS -o "$OUT" -w '%{http_code}' -L "$URL" 2>/dev/null || echo 000)
  if [[ $code == 404 || $code == 000 ]]; then
    rm -f "$OUT"
    exit 0
  fi
  [[ $code =~ ^2 ]] && exit 0
  exit 1
fi

exec /usr/bin/curl \
  --proxy "$PROXY" \
  --connect-timeout 30 \
  --retry 5 \
  --retry-all-errors \
  --retry-delay 3 \
  --http1.1 \
  -L -C - -f "$URL" -o "$OUT"
