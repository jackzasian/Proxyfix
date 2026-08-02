#!/bin/bash
# Pacman XferCommand wrapper — route every download through Clash mixed port.
# Outer retry loop: Clash nodes sometimes drop TLS handshakes (curl 35).
set -euo pipefail

PROXY="${PACMAN_PROXY_URL:-http://127.0.0.1:7897}"
URL=$1
OUT=$2
MAX_ATTEMPTS="${PACMAN_CURL_ATTEMPTS:-20}"

# geo.mirror.pkgbuild.com and pkgs.omarchy.org omit optional repo *.db.sig / *.files.sig.
# pacman.conf uses DatabaseOptional — missing repo signatures are OK.
# Exit non-zero on missing sigs so pacman does not try to rename a deleted .part file.
if [[ $URL == *.db.sig || $URL == *.files.sig ]]; then
  code=$(/usr/bin/curl \
    --proxy "$PROXY" \
    --connect-timeout 20 \
    --retry 1 \
    --http1.1 \
    -sS -o "$OUT" -w '%{http_code}' -L "$URL" 2>/dev/null || echo 000)
  if [[ $code == 404 || $code == 000 ]]; then
    rm -f "$OUT"
    exit 1
  fi
  [[ $code =~ ^2 ]] && exit 0
  exit 1
fi

attempt=1
while (( attempt <= MAX_ATTEMPTS )); do
  if /usr/bin/curl \
    --proxy "$PROXY" \
    --connect-timeout 20 \
    --retry 2 \
    --retry-all-errors \
    --retry-delay 1 \
    --http1.1 \
    --no-keepalive \
    -L -C - -f "$URL" -o "$OUT"; then
    exit 0
  fi
  rm -f "${OUT}.part" 2>/dev/null || true
  sleep $(( attempt < 5 ? 1 : 3 ))
  attempt=$((attempt + 1))
done

exit 1
