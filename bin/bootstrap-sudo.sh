#!/usr/bin/env bash
# One-shot sudo setup: curl-proxy db.sig fix + pacman proxy sudoers. Run in a real terminal.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SKILL="${HOME}/.cursor/skills/omarchy-pacman-proxy"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "=== proxyfix bootstrap (needs sudo) ==="
  echo "Authenticate when prompted (fingerprint or password)."
  exec sudo bash "$0"
fi

bash "${REPO}/bin/install-curl-proxy.sh"

SUDOERS_SRC="${SKILL}/templates/etc/sudoers.d/99-pacman-proxy-env"
if [[ -f $SUDOERS_SRC ]]; then
  install -m 0440 "$SUDOERS_SRC" /etc/sudoers.d/99-pacman-proxy-env
  visudo -cf /etc/sudoers.d/99-pacman-proxy-env
  echo "Installed /etc/sudoers.d/99-pacman-proxy-env"
fi

echo ""
echo "Testing db.sig + files.sig (should exit 0, no retry spam):"
set +e
/etc/pacman.d/curl-proxy.sh "https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db.sig" /tmp/t.sig
echo "db.sig exit: $?"
/etc/pacman.d/curl-proxy.sh "https://geo.mirror.pkgbuild.com/core/os/x86_64/core.files.sig" /tmp/t.files.sig
echo "files.sig exit: $?"
set -e
rm -f /tmp/t.sig /tmp/t.files.sig

echo ""
echo "Testing core.db download:"
TEST_DB=$(mktemp /tmp/pacman-proxy-test.XXXXXX.db)
/etc/pacman.d/curl-proxy.sh "https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db" "$TEST_DB"
rm -f "$TEST_DB"
echo "Done. Sync repos: sudo pacman -Syy"
