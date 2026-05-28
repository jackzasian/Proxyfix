#!/usr/bin/env bash
# Shared helpers for proxyfix.

PROXYFIX_ROOT="${PROXYFIX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CLASH_DIR="${CLASH_DIR:-${HOME}/.local/share/io.github.clash-verge-rev.clash-verge-rev}"
CLASH_SOCK="${CLASH_SOCK:-/tmp/verge/verge-mihomo.sock}"
CLASH_CFG="${CLASH_CFG:-${CLASH_DIR}/config.yaml}"
CLASH_RUNTIME="${CLASH_RUNTIME:-${CLASH_DIR}/clash-verge.yaml}"
CLASH_DNS_CFG="${CLASH_DNS_CFG:-${CLASH_DIR}/dns_config.yaml}"
MANIFEST="${MANIFEST:-${PROXYFIX_ROOT}/manifests/apps.yaml}"
LOG_DIR="${LOG_DIR:-${HOME}/.local/share/proxyfix}"
PROXY_SH="${PROXY_SH:-${HOME}/.config/omarchy/proxy.sh}"
CURSOR_SETTINGS="${CURSOR_SETTINGS:-${HOME}/.config/Cursor/User/settings.json}"
ELECTRON_FLAGS="${ELECTRON_FLAGS:-${HOME}/.config/electron-flags.conf}"

ok()   { [[ -z ${QUIET:-} ]] && printf '\033[32m✓\033[0m %s\n' "$*" || logger -t proxyfix "OK: $*"; }
warn() { [[ -z ${QUIET:-} ]] && printf '\033[33m!\033[0m %s\n' "$*" || logger -t proxyfix "WARN: $*"; }
fail() { [[ -z ${QUIET:-} ]] && printf '\033[31m✗\033[0m %s\n' "$*" || logger -t proxyfix "FAIL: $*"; }
info() { [[ -z ${QUIET:-} ]] && printf '  %s\n' "$*" || true; }

mixed_port() {
  if [[ -f $CLASH_CFG ]]; then
    awk '/^mixed-port:/ {print $2; exit}' "$CLASH_CFG"
  elif [[ -f ${CLASH_DIR}/verge.yaml ]]; then
    awk '/^verge_mixed_port:/ {print $2; exit}' "${CLASH_DIR}/verge.yaml"
  else
    echo 7897
  fi
}

clash_up() {
  [[ -S $CLASH_SOCK ]] && curl -sS --max-time 2 --unix-socket "$CLASH_SOCK" http://localhost/ 2>/dev/null \
    | grep -q '"hello":"mihomo"'
}

wait_for_clash() {
  local max="${1:-60}" i
  for ((i = 1; i <= max; i++)); do
    clash_up && return 0
    sleep 1
  done
  return 1
}

reload_mihomo() {
  if [[ -S $CLASH_SOCK && -f $CLASH_RUNTIME ]]; then
    curl -sfS --max-time 5 --unix-socket "$CLASH_SOCK" -X PUT "http://localhost/configs" \
      -H 'Content-Type: application/json' \
      -d "{\"path\":\"${CLASH_RUNTIME}\"}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

flush_dns() {
  resolvectl flush-caches 2>/dev/null || true
}

host_resolves_fake_ip() {
  local host=$1 ip
  ip=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | head -1 || true)
  [[ ${ip:-} == 198.18.* ]]
}

merge_profile_path() {
  python3 - "$MANIFEST" <<'PY'
import re, sys
from pathlib import Path

manifest = Path(sys.argv[1])
clash_dir = Path.home() / ".local/share/io.github.clash-verge-rev.clash-verge-rev"
name = "mrkG4UPD40Es.yaml"
if manifest.exists():
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if line.startswith("merge_profile:"):
            name = line.split(":", 1)[1].strip()
            break
print(clash_dir / "profiles" / name)
PY
}

log_run() {
  mkdir -p "$LOG_DIR"
  {
    date -Iseconds
    echo "app_filter=${APP_FILTER:-all}"
  } >"${LOG_DIR}/last-run.log"
}
