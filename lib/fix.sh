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

fix_clash_pac_file() {
  local port=${1:-$(mixed_port)}
  local pac="${HOME}/.config/omarchy/clash-proxy.pac"
  mkdir -p "$(dirname "$pac")"
  if [[ ! -f $pac ]]; then
    cat >"$pac" <<EOF
// Omarchy PAC — Strava bypasses Clash (real CN IP). Updated by proxyfix.
function hostMatchesStrava(host) {
  host = host.toLowerCase();
  if (host === "localhost" || host === "127.0.0.1" || host === "::1")
    return true;
  if (dnsDomainIs(host, ".strava.com") || host === "strava.com")
    return true;
  if (host.indexOf("strava") !== -1)
    return true;
  var cdn = [
    "d3nn82uaxijpm6.cloudfront.net",
    "dgtzuqphqg23d.cloudfront.net",
    "dgalywyr863hv.cloudfront.net",
    "d3o5xota0a1fcr.cloudfront.net",
    "d21y75miwcfqoq.cloudfront.net",
    "d3u3hkafyj3iak.cloudfront.net"
  ];
  for (var i = 0; i < cdn.length; i++)
    if (host === cdn[i])
      return true;
  return false;
}
function FindProxyForURL(url, host) {
  if (hostMatchesStrava(host))
    return "DIRECT";
  return "PROXY 127.0.0.1:${port}; SOCKS5 127.0.0.1:${port}; DIRECT;";
}
EOF
  else
    sed -i "s/127.0.0.1:[0-9]\+/127.0.0.1:${port}/g" "$pac"
  fi
}

fix_chromium_flags() {
  local port url tmp
  port=$(mixed_port)
  url="http://127.0.0.1:${port}"
  mkdir -p "$(dirname "$CHROMIUM_FLAGS")"
  tmp=$(mktemp)
  if [[ -f $CHROMIUM_FLAGS ]]; then
    grep -vE '^--proxy-server=|^--proxy-bypass-list=|^--proxy-pac-url=' "$CHROMIUM_FLAGS" \
      | grep -v '^# Chromium.*Clash' >"$tmp" || true
  else
    : >"$tmp"
  fi
  {
    cat "$tmp"
    printf '%s\n' \
      "# Chromium — full Clash proxy (Strava via proxy) — updated by proxyfix" \
      "--proxy-server=${url}"
  } >"$CHROMIUM_FLAGS"
  rm -f "$tmp"
  ok "chromium-flags.conf → ${url} (full proxy)"
}

fix_zen_pac() {
  local port pac zen_user
  port=$(mixed_port)
  pac="${HOME}/.config/omarchy/clash-proxy.pac"
  fix_clash_pac_file "$port"
  for zen_user in "${HOME}/.config/zen/"*/user.js; do
    [[ -f $zen_user ]] || continue
    if ! grep -q 'clash-proxy.pac' "$zen_user" 2>/dev/null; then
      {
        echo ""
        echo "// proxyfix — Strava needs direct CN IP (not Clash proxy location)"
        echo 'user_pref("network.proxy.type", 2);'
        echo "user_pref(\"network.proxy.autoconfig_url\", \"file://${pac}\");"
      } >>"$zen_user"
      ok "Zen PAC → ${pac} (${zen_user})"
    else
      ok "Zen PAC already set (${zen_user})"
    fi
  done
}

verify_launch_wrappers() {
  local f
  for f in cursor-launch claude-desktop-launch steam-launch chromium-launch-webapp anki-launch; do
    if [[ -x "${HOME}/.local/bin/${f}" ]]; then
      ok "launch wrapper: ${f}"
    else
      warn "missing launch wrapper: ~/.local/bin/${f}"
    fi
  done
}

fix_git_proxy() {
  local port url
  port=$(mixed_port)
  url="http://127.0.0.1:${port}"
  git config --global http.proxy "$url"
  git config --global https.proxy "$url"
  ok "git proxy → ${url}"
}

fix_gnome_proxy() {
  command -v gsettings >/dev/null 2>&1 || return 0
  local port host
  port=$(mixed_port)
  host=127.0.0.1
  gsettings set org.gnome.system.proxy mode manual
  gsettings set org.gnome.system.proxy use-same-proxy true
  gsettings set org.gnome.system.proxy.http host "$host"
  gsettings set org.gnome.system.proxy.http port "$port"
  gsettings set org.gnome.system.proxy.http enabled true
  gsettings set org.gnome.system.proxy.https host "$host"
  gsettings set org.gnome.system.proxy.https port "$port"
  gsettings set org.gnome.system.proxy.https enabled true 2>/dev/null || true
  gsettings set org.gnome.system.proxy.socks host "$host"
  gsettings set org.gnome.system.proxy.socks port "$port"
  python3 - <<'PY'
import subprocess
extra = ["*.strava.com", "strava.com", "www.strava.com"]
raw = subprocess.check_output(
    ["gsettings", "get", "org.gnome.system.proxy", "ignore-hosts"],
    text=True,
).strip()
if raw.startswith("["):
    hosts = [h.strip().strip("'") for h in raw.strip("[]").split(",") if h.strip()]
else:
    hosts = []
for h in extra:
    if h not in hosts:
        hosts.append(h)
quoted = ", ".join(f"'{h}'" for h in hosts)
subprocess.run(
    ["gsettings", "set", "org.gnome.system.proxy", "ignore-hosts", f"[{quoted}]"],
    check=True,
)
PY
  ok "GNOME/GTK proxy → ${host}:${port} (Wike, WebKit, libsoup)"
}

fix_pacman_report() {
  local verify="${HOME}/.local/bin/omarchy-pacman-proxy-verify"
  local installer="${PROXYFIX_ROOT}/bin/install-curl-proxy.sh"
  if [[ -x $installer ]] && ! grep -q 'files\.sig' /etc/pacman.d/curl-proxy.sh 2>/dev/null; then
    warn "pacman curl-proxy needs db/files.sig fix — run: ${installer}"
  fi
  [[ -x $verify ]] || return
  if ! "$verify" >/dev/null 2>&1; then
    warn "pacman proxy broken — run: omarchy-pacman-proxy-restore OR ${installer}"
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
    all|clash|steam|cursor|discord|pacman|strava)
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
    fix_chromium_flags
  fi

  if [[ $APP_FILTER == all || $APP_FILTER == git ]]; then
    fix_git_proxy
  fi

  if [[ $APP_FILTER == all || $APP_FILTER == gtk ]]; then
    fix_gnome_proxy
    fix_zen_pac
  fi

  if [[ $APP_FILTER == all ]]; then
    verify_launch_wrappers
    fix_pacman_report
  fi

  # Interactive runs only — quiet timer must not trigger polkit DNS-flush auth.
  # NOTE: trailing || true on these guards — in quiet mode a bare
  # `[[ -z ${QUIET} ]] && …` returns 1, and as main()'s last command that
  # becomes the script's exit status (systemd then reports a false failure).
  [[ -z ${QUIET:-} ]] && flush_dns || true
  log_run

  [[ -z ${QUIET:-} ]] && printf '\n--- Re-check ---\n' || true
  QUIET=${QUIET:-} bash "${SCRIPT_DIR}/detect.sh" || true

  [[ -z ${QUIET:-} ]] && printf '\nDone.' || true
  [[ -z ${QUIET:-} && ($APP_FILTER == all || $APP_FILTER == cursor) ]] && \
    printf ' Fully quit Cursor and reopen via cursor-launch for electron flags.\n\n' || true
}

main "$@"
