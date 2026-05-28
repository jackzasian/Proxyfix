#!/usr/bin/env bash
# Orchestrate detect → patch → per-app fixes → re-detect
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

APP_FILTER="${APP_FILTER:-all}"
FIX_ONLY=false
[[ ${1:-} == "--detect-only" ]] && FIX_ONLY=true

fix_clash_security() {
  if command -v clash-secure-localhost >/dev/null 2>&1; then
    clash-secure-localhost && ok "Clash localhost security applied" || warn "clash-secure-localhost warnings"
  fi
}

fix_shell_proxy() {
  [[ -f $PROXY_SH ]] || { warn "Missing ${PROXY_SH}"; return; }
  # shellcheck source=/dev/null
  source "$PROXY_SH"
  if proxy_on >/dev/null 2>&1; then
    ok "Shell proxy enabled"
  else
    warn "proxy_on failed (Clash down?)"
  fi
}

fix_cursor_settings() {
  local port url
  port=$(mixed_port)
  url="http://127.0.0.1:${port}"
  mkdir -p "$(dirname "$CURSOR_SETTINGS")"
  [[ -f $CURSOR_SETTINGS ]] || printf '{}\n' >"$CURSOR_SETTINGS"
  python3 - "$CURSOR_SETTINGS" "$url" <<'PY'
import json, sys
path, url = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        data = {}
data["http.proxy"] = url
data["http.proxySupport"] = "override"
data["http.proxyStrictSSL"] = False
data["http.noProxy"] = ["localhost", "127.0.0.1", "::1", "10.0.0.0/8", "192.168.0.0/16"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY
  ok "Cursor settings → ${url}"
}

fix_electron_flags() {
  local port
  port=$(mixed_port)
  mkdir -p "$(dirname "$ELECTRON_FLAGS")"
  cat >"$ELECTRON_FLAGS" <<EOF
# Electron/Chromium flags — required with Clash TUN fake-ip
# Updated by proxyfix
--proxy-server=http://127.0.0.1:${port}
EOF
  ok "electron-flags.conf → port ${port}"
}

verify_launch_wrappers() {
  local f
  for f in cursor-launch steam-launch chromium-launch-webapp; do
    if [[ -x "${HOME}/.local/bin/${f}" ]]; then
      ok "launch wrapper: ${f}"
    else
      warn "missing launch wrapper: ~/.local/bin/${f}"
    fi
  done
}

fix_pacman_report() {
  local verify="${HOME}/.local/bin/omarchy-pacman-proxy-verify"
  [[ -x $verify ]] || return
  if ! "$verify" >/dev/null 2>&1; then
    warn "pacman proxy broken — run: omarchy-pacman-proxy-restore"
  fi
}

main() {
  [[ -z ${QUIET:-} ]] && printf '\n=== proxyfix fix ===\n\n'

  if ! wait_for_clash 60; then
    fail "Clash not running after 60s — start Clash Verge, then re-run proxyfix fix"
    exit 1
  fi
  ok "Clash is up"

  local patch_app=$APP_FILTER
  [[ $patch_app == clash ]] && patch_app=all
  case "$APP_FILTER" in
    all|clash|steam|cursor|discord|pacman)
      [[ -z ${QUIET:-} ]] && printf '\n--- Clash DNS / rules ---\n'
      bash "${SCRIPT_DIR}/patch-clash.sh" "$patch_app"
      ;;
  esac

  if [[ $APP_FILTER == all || $APP_FILTER == clash ]]; then
    fix_clash_security
  fi

  if [[ $APP_FILTER == all || $APP_FILTER == shell ]]; then
    fix_shell_proxy
  fi

  if [[ $APP_FILTER == all || $APP_FILTER == cursor ]]; then
    fix_cursor_settings
    fix_electron_flags
  fi

  if [[ $APP_FILTER == all ]]; then
    verify_launch_wrappers
    fix_pacman_report
  fi

  flush_dns
  log_run

  [[ -z ${QUIET:-} ]] && printf '\n--- Re-check ---\n'
  QUIET=${QUIET:-} bash "${SCRIPT_DIR}/detect.sh" || true

  [[ -z ${QUIET:-} ]] && printf '\nDone.'
  [[ -z ${QUIET:-} && ($APP_FILTER == all || $APP_FILTER == cursor) ]] && \
    printf ' Fully quit Cursor and reopen via cursor-launch for electron flags.\n\n'
}

main "$@"
