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
CHROMIUM_FLAGS="${CHROMIUM_FLAGS:-${HOME}/.config/chromium-flags.conf}"

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
  # resolvectl flush-caches needs polkit (fingerprint/password on this machine).
  # Skip during quiet timer runs so proxyfix.timer doesn't nag every 10 minutes.
  if [[ -n ${QUIET:-} || -n ${PROXYFIX_SKIP_DNS_FLUSH:-} ]]; then
    return 0
  fi
  resolvectl flush-caches 2>/dev/null || true
}

host_resolves_fake_ip() {
  local host=$1 ip
  ip=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | head -1 || true)
  [[ ${ip:-} == 198.18.* ]]
}

PROFILE_RESOLVER="${PROFILE_RESOLVER:-${PROXYFIX_ROOT}/lib/resolve-profiles.py}"

# Clash Verge names profile files after per-install UIDs, so they cannot be
# hardcoded. Resolve the active chain once; any PROXYFIX_*_PROFILE already
# present in the environment wins so the chain can be pinned or tested.
proxyfix_resolve_profiles() {
  [[ -n ${PROXYFIX_PROFILES_RESOLVED:-} ]] && return 0
  declare -g PROXYFIX_PROFILES_RESOLVED=1
  local key value
  while IFS='=' read -r key value; do
    [[ -z $key || -z $value ]] && continue
    [[ -n ${!key:-} ]] && continue
    declare -g "${key}=${value}"
  done < <(python3 "$PROFILE_RESOLVER" "$CLASH_DIR" 2>/dev/null || true)
  return 0
}

# Read a scalar key from manifests/apps.yaml.
manifest_value() {
  local key=$1
  [[ -f $MANIFEST ]] || return 0
  awk -v k="^${key}:" '$0 ~ k { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$MANIFEST"
}

# Precedence: manifest override → auto-detected chain → Verge's global Merge.yaml.
profile_path() {
  local kind=$1 var="PROXYFIX_${1^^}_PROFILE" name
  name=$(manifest_value "${kind}_profile")
  if [[ -z $name || $name == auto ]]; then
    proxyfix_resolve_profiles
    name=${!var:-}
  fi
  [[ -z $name && $kind == merge ]] && name="Merge.yaml"
  [[ -z $name ]] && return 1
  printf '%s\n' "${CLASH_DIR}/profiles/${name}"
}

merge_profile_path() { profile_path merge; }
rules_profile_path() { profile_path rules; }

log_run() {
  mkdir -p "$LOG_DIR"
  {
    date -Iseconds
    echo "app_filter=${APP_FILTER:-all}"
  } >"${LOG_DIR}/last-run.log"
}
