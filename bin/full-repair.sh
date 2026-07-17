#!/usr/bin/env bash
# Full repair: sudo pacman fix → proxyfix → omarchy update. Run in a real terminal.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo "=== Step 1/3: Install curl-proxy fix (stops 404 spam) ==="
bash "${REPO}/bin/bootstrap-sudo.sh"

echo ""
echo "=== Step 2/3: proxyfix ==="
"${REPO}/proxyfix" fix

echo ""
echo "=== Step 3/3: omarchy update ==="
if command -v omarchy-update >/dev/null 2>&1; then
  omarchy-update -y
else
  omarchy update -y
fi

echo ""
echo "=== Done. Reboot if kernel/systemd updated. ==="
