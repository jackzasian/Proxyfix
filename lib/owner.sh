#!/usr/bin/env bash
# Configuration reserves ownership even when its daemon is temporarily offline.
proxy_owner_is_relaypilot() {
  [[ -f "$HOME/.config/relaypilot/config.yaml" ]] ||
    [[ -f "$HOME/.config/proxy-owner" && $(cat "$HOME/.config/proxy-owner") == relaypilot ]]
}

proxy_owner_refuse_legacy_repair() {
  printf '%s\n' 'RelayPilot owns this proxy. Legacy Clash repair is blocked; the running proxy is unchanged.' >&2
  printf '%s\n' 'Check: relaypilotd --config ~/.config/relaypilot/config.yaml status' >&2
  return 2
}
