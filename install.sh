#!/usr/bin/env bash
# Install proxyfix: symlink, systemd units, Clash startup script, omarchy hook.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN="${HOME}/.local/bin/proxyfix"
SYSTEMD="${HOME}/.config/systemd/user"
CLASH_DIR="${HOME}/.local/share/io.github.clash-verge-rev.clash-verge-rev"
VERGE_YAML="${CLASH_DIR}/verge.yaml"
HOOK="${HOME}/.config/omarchy/hooks/post-update"

ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }

chmod +x "${REPO}/proxyfix" "${REPO}/lib/"*.sh "${REPO}/bin/"*

mkdir -p "${HOME}/.local/bin" "${SYSTEMD}" "${HOME}/.local/share/proxyfix"

ln -sf "${REPO}/proxyfix" "$BIN"
ok "Symlink: ${BIN} → ${REPO}/proxyfix"

cat >"${SYSTEMD}/proxyfix.service" <<EOF
[Unit]
Description=Proxyfix — detect and repair Clash proxy settings

[Service]
Type=oneshot
ExecStart=${REPO}/bin/proxyfix-guard
Environment=HOME=${HOME}
EOF
ok "Wrote ${SYSTEMD}/proxyfix.service"

cat >"${SYSTEMD}/proxyfix.path" <<EOF
[Unit]
Description=Run proxyfix when Clash config changes

[Path]
PathChanged=${CLASH_DIR}/config.yaml
PathChanged=${CLASH_DIR}/clash-verge.yaml
PathChanged=${CLASH_DIR}/dns_config.yaml
PathChanged=${CLASH_DIR}/profiles/mrkG4UPD40Es.yaml
PathChanged=${CLASH_DIR}/profiles/RM0FPXAv4fiC.yaml

[Install]
WantedBy=paths.target
EOF
ok "Wrote ${SYSTEMD}/proxyfix.path"

cat >"${SYSTEMD}/proxyfix.timer" <<EOF
[Unit]
Description=Periodic proxyfix check

[Timer]
OnBootSec=3min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF
ok "Wrote ${SYSTEMD}/proxyfix.timer"

systemctl --user daemon-reload
systemctl --user enable proxyfix.path proxyfix.timer
systemctl --user start proxyfix.path proxyfix.timer
ok "Enabled proxyfix.path and proxyfix.timer"

NET_SVC="${SYSTEMD}/proxyfix-network.service"
cat >"$NET_SVC" <<EOF
[Unit]
Description=Proxyfix network change monitor

[Service]
Type=simple
ExecStart=${REPO}/bin/proxyfix-network-monitor
Restart=on-failure
RestartSec=10
Environment=HOME=${HOME}

[Install]
WantedBy=default.target
EOF
chmod +x "${REPO}/bin/proxyfix-network-monitor"
systemctl --user enable proxyfix-network.service
systemctl --user start proxyfix-network.service 2>/dev/null || true
ok "Enabled proxyfix-network.service"

if [[ -f $VERGE_YAML ]]; then
  if grep -q '^startup_script:' "$VERGE_YAML"; then
    python3 - "$VERGE_YAML" "$BIN" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
bin_path = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
out = []
done = False
for line in lines:
    if line.startswith("startup_script:"):
        out.append(f"startup_script: {bin_path} fix --quiet")
        done = True
    else:
        out.append(line)
if not done:
    out.append(f"startup_script: {bin_path} fix --quiet")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
print("OK")
PY
    ok "Set Clash Verge startup_script → proxyfix fix --quiet"
  else
    warn "verge.yaml has no startup_script key — add manually"
  fi
fi

MARKER="# proxyfix post-update"
if [[ -f $HOOK ]]; then
  if ! grep -qF "$MARKER" "$HOOK"; then
    cat >>"$HOOK" <<EOF

$MARKER
proxyfix fix --quiet || true
command -v omarchy-pacman-proxy-verify >/dev/null && omarchy-pacman-proxy-verify || true
EOF
    ok "Appended proxyfix to omarchy post-update hook"
  else
    ok "omarchy post-update hook already has proxyfix"
  fi
else
  mkdir -p "$(dirname "$HOOK")"
  cat >"$HOOK" <<EOF
#!/bin/bash
$MARKER
proxyfix fix --quiet || true
command -v omarchy-pacman-proxy-verify >/dev/null && omarchy-pacman-proxy-verify || true
EOF
  chmod +x "$HOOK"
  ok "Created omarchy post-update hook with proxyfix"
fi

printf '\nInstall complete. Run: proxyfix fix\n\n'
