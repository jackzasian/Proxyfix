#!/usr/bin/env bash
# Detect proxy / Clash health issues. Exit 1 if any issue found.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

ISSUES=()

add_issue() { ISSUES+=("$1"); }

check_clash_up() {
  if ! clash_up; then
    add_issue "clash_down"
    fail "Clash mihomo is not running"
    return 1
  fi
  ok "Clash mihomo API is up"
}

check_security() {
  local cfg=$CLASH_CFG allow_lan bind
  [[ -f $cfg ]] || return 0
  if grep -qE '^allow-lan:[[:space:]]*true' "$cfg" 2>/dev/null; then
    add_issue "allow_lan_true"
    fail "allow-lan is true in config.yaml"
  fi
  if ! grep -qE '^bind-address:[[:space:]]*127\.0\.0\.1' "$cfg" 2>/dev/null; then
    add_issue "bind_address"
    fail "bind-address not 127.0.0.1 in config.yaml"
  fi
  if ! printf '%s\n' "${ISSUES[@]}" | grep -qE 'allow_lan|bind_address'; then
    ok "Clash localhost security settings OK"
  fi
}

check_manifest_in_merge() {
  local merge
  merge=$(merge_profile_path)
  [[ -f $merge ]] || { add_issue "merge_missing"; fail "Merge profile missing: $merge"; return; }
  python3 - "$MANIFEST" "$merge" <<'PY'
import re, sys
from pathlib import Path

manifest = Path(sys.argv[1]).read_text(encoding="utf-8")
merge = Path(sys.argv[2]).read_text(encoding="utf-8")
domains = []
key = None
for line in manifest.splitlines():
    if line.strip() == "fake_ip_filter:":
        key = "fake"
        continue
    if key == "fake" and re.match(r"^\s+-\s+", line):
        val = line.strip()[2:].strip().strip("'\"")
        if not val.startswith("#"):
            domains.append(val)
    elif line and not line.startswith(" ") and not line.startswith("#"):
        if key == "fake":
            break

missing = [d for d in domains if d not in merge]
if missing:
    for d in missing[:5]:
        print(f"MISSING:{d}")
    if len(missing) > 5:
        print(f"MISSING:+{len(missing)-5} more")
    sys.exit(1)
sys.exit(0)
PY
  if [[ $? -ne 0 ]]; then
    add_issue "merge_incomplete"
    fail "Merge profile missing fake-ip-filter entries"
  else
    ok "Merge profile has manifest domains"
  fi
}

check_probe_hosts() {
  local host ip
  while IFS= read -r host; do
    [[ -z $host || $host =~ ^# ]] && continue
    if host_resolves_fake_ip "$host"; then
      ip=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | head -1)
      add_issue "fake_ip:${host}"
      fail "${host} → fake-ip ${ip}"
    else
      ip=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | head -1 || echo "?")
      ok "${host} → ${ip}"
    fi
  done < <(python3 - "$MANIFEST" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
in_probes = False
for line in text.splitlines():
    if line.strip() == "probe_hosts:":
        in_probes = True
        continue
    if in_probes and re.match(r"^\s+-\s+", line):
        print(line.strip()[2:].strip().strip("'\""))
    elif in_probes and line and not line.startswith(" "):
        break
PY
)
}

check_electron_flags() {
  local port url
  port=$(mixed_port)
  url="http://127.0.0.1:${port}"
  if [[ ! -f $ELECTRON_FLAGS ]] || ! grep -qF "127.0.0.1:${port}" "$ELECTRON_FLAGS" 2>/dev/null; then
    add_issue "electron_flags"
    fail "electron-flags.conf missing or wrong port (want ${url})"
  else
    ok "electron-flags.conf → ${url}"
  fi
}

check_chromium_flags() {
  local port url
  port=$(mixed_port)
  url="http://127.0.0.1:${port}"
  if [[ ! -f $CHROMIUM_FLAGS ]] || ! grep -qF "127.0.0.1:${port}" "$CHROMIUM_FLAGS" 2>/dev/null; then
    add_issue "chromium_flags"
    fail "chromium-flags.conf missing or wrong port (want ${url})"
  else
    ok "chromium-flags.conf → ${url}"
  fi
}

check_cursor_settings() {
  local port url
  port=$(mixed_port)
  url="http://127.0.0.1:${port}"
  if [[ ! -f $CURSOR_SETTINGS ]]; then
    add_issue "cursor_settings"
    fail "Cursor settings.json missing"
    return
  fi
  python3 - "$CURSOR_SETTINGS" "$url" <<'PY'
import json, sys
path, url = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    d = json.load(f)
ok = d.get("http.proxy") == url and d.get("http.proxySupport") == "override"
sys.exit(0 if ok else 1)
PY
  if [[ $? -ne 0 ]]; then
    add_issue "cursor_settings"
    fail "Cursor settings: http.proxy or proxySupport=override wrong"
  else
    ok "Cursor settings proxy OK"
  fi
}

check_gnome_proxy() {
  command -v gsettings >/dev/null 2>&1 || return 0
  local port mode http_enabled http_port
  port=$(mixed_port)
  mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "''")
  http_enabled=$(gsettings get org.gnome.system.proxy.http enabled 2>/dev/null || echo false)
  http_port=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null || echo 0)
  if [[ $mode != "'manual'" || $http_enabled != true || $http_port != "$port" ]]; then
    add_issue "gnome_proxy"
    fail "GNOME proxy off or wrong (GTK apps like Wike need manual + http enabled + port ${port})"
  else
    ok "GNOME/GTK proxy OK"
  fi
}

check_pacman_proxy() {
  local verify="${HOME}/.local/bin/omarchy-pacman-proxy-verify"
  [[ -x $verify ]] || return 0
  if ! "$verify" >/dev/null 2>&1; then
    add_issue "pacman_proxy"
    warn "pacman-via-proxy config needs attention (run omarchy-pacman-proxy-restore)"
  else
    ok "pacman-via-proxy verify OK"
  fi
}

check_connectivity() {
  local url name
  while IFS= read -r line; do
    name="${line%%|*}"
    url="${line#*|}"
    # Retries: Clash nodes intermittently drop TLS handshakes (curl 35);
    # a single-attempt check makes detect flappy without a real outage.
    if curl -sS --max-time 12 --retry 2 --retry-all-errors --retry-delay 1 \
         -o /dev/null -w '' "$url" 2>/dev/null; then
      ok "HTTPS → ${name}"
    else
      add_issue "connectivity:${name}"
      warn "HTTPS failed → ${name}"
    fi
  done <<EOF
google|https://www.google.com
cursor-api|https://api2.cursor.sh
steam-store|https://store.steampowered.com
aur|https://aur.archlinux.org
EOF
}

# Routing policy: Spotify=HK, Claude/Cursor/OpenCode=US (degraded last hop allowed)
check_routing_policy() {
  local runtime rules_ok=1
  runtime="${CLASH_RUNTIME:-${CLASH_DIR}/clash-verge.yaml}"
  [[ -f $runtime ]] || return 0

  if ! grep -qE 'DOMAIN-SUFFIX,cursor\.sh,美国故障转移' "$runtime" 2>/dev/null; then
    add_issue "routing_cursor_us"
    fail "cursor.sh not routed to 美国故障转移 (see ROUTING.md)"
    rules_ok=0
  fi
  if ! grep -qE 'DOMAIN-SUFFIX,anthropic\.com,美国故障转移' "$runtime" 2>/dev/null; then
    add_issue "routing_claude_us"
    fail "anthropic.com not routed to 美国故障转移"
    rules_ok=0
  fi
  if ! grep -qE 'DOMAIN-SUFFIX,spotify\.com,香港故障转移' "$runtime" 2>/dev/null; then
    add_issue "routing_spotify_hk"
    fail "spotify.com not routed to 香港故障转移"
    rules_ok=0
  fi
  if ! grep -qE 'DOMAIN-SUFFIX,opencode\.ai,美国故障转移' "$runtime" 2>/dev/null; then
    add_issue "routing_opencode_us"
    fail "opencode.ai not routed to 美国故障转移"
    rules_ok=0
  fi
  if ((rules_ok)); then
    ok "Routing rules: Claude/Cursor/OpenCode→US, Spotify→HK"
  fi

  clash_up || return 0
  local now members alive_us
  now=$(curl -sS --max-time 3 --unix-socket "$CLASH_SOCK" http://localhost/proxies 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin)["proxies"];
us=d.get("美国故障转移") or {}; print(us.get("now") or "?");
print(",".join(us.get("all") or []));
print(sum(1 for n in ("美国aw1","美国aw2","美国aw3","美国aw4","美国1","美国2") if (d.get(n) or {}).get("alive")))' 2>/dev/null) || true
  if [[ -z $now ]]; then
    warn "Could not query US group health via API"
    return 0
  fi
  members=$(printf '%s\n' "$now" | sed -n '2p')
  alive_us=$(printf '%s\n' "$now" | sed -n '3p')
  now=$(printf '%s\n' "$now" | sed -n '1p')
  if [[ $members != *自动选择* ]]; then
    add_issue "us_no_degraded_hop"
    fail "美国故障转移 missing 自动选择 degraded hop (now=${now})"
  else
    info "美国故障转移 now=${now} members=${members}"
  fi
  if [[ ${alive_us:-0} -eq 0 ]]; then
    warn "All 极客云 US leaves dead — 美国故障转移 may be on Dualnet/自动选择 (degraded)"
  else
    ok "US nodes: ${alive_us} 极客云 US leaf(s) alive"
  fi
}

main() {
  [[ -z ${QUIET:-} ]] && printf '\n=== proxyfix detect ===\n\n'
  check_clash_up || true
  if clash_up; then
    check_security
    check_manifest_in_merge
    check_probe_hosts
    check_electron_flags
    check_chromium_flags
    check_cursor_settings
    check_gnome_proxy
    check_pacman_proxy
    check_connectivity
    check_routing_policy
  fi
  [[ -z ${QUIET:-} ]] && printf '\n'
  if ((${#ISSUES[@]} > 0)); then
    info "Issues: ${ISSUES[*]}"
    return 1
  fi
  [[ -z ${QUIET:-} ]] && ok "All checks passed"
  return 0
}

main "$@"
