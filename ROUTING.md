# Proxyfix routing policy

**Last updated:** 2026-08-06

Preferred exits for jackz's ThinkPad (Clash Verge Rev / mihomo, mixed port `7897`).

## Policy table

| Traffic | Group | Provider chain | Why |
|---------|-------|----------------|-----|
| Spotify (app + CDN) | `香港故障转移` | `香港自动` → `Dualnet香港` | HK library / latency |
| Claude, Claude Code, Claude Design | `美国故障转移` | `us自动切换` → `Dualnet美国` → `自动选择` | Anthropic geo |
| Cursor agent / Cursor APIs | `美国故障转移` | same | Prefer US for agent backends |
| OpenCode (+ OpenAI if used) | `美国故障转移` | same | Prefer US for model APIs |
| Steam / HF / large CDN | `DIRECT` | — | Speed through GFW direct |
| Tailscale / homelab | `DIRECT` | — | Never hijack `100.64/10` |
| Everything else (`MATCH`) | `故障转移` | `自动选择` → `Dualnet` | Lowest latency (often JP) |

## Groups (enhancement `gHDtD8h76ZHx.yaml`)

- **`美国故障转移`** (fallback): first alive wins; reverts when higher priority recovers.
  1. `us自动切换` — 极客云 US nodes only
  2. `Dualnet美国` — Dual+Net US filter
  3. `自动选择` — **degraded hop** when every US node is dead (keeps Claude/Cursor usable via JP instead of hanging)
- **`香港故障转移`**: `香港自动` → `Dualnet香港` (no non-HK fallback — Spotify must stay HK)
- **`故障转移`**: default MATCH — latency, not geo

## Source of truth

| File | Role |
|------|------|
| `manifests/apps.yaml` | Domains / process rules proxyfix reinjects |
| Clash rules profile `rT8qps5nUb4g.yaml` | Verge rules enhancement |
| Clash groups profile `gHDtD8h76ZHx.yaml` | Failover groups |
| Clash merge `mrkG4UPD40Es.yaml` | fake-ip-filter, security, dualnet provider |

## Debugging cheatsheet

```bash
# Structural health (fake-ip, ports, settings) — does NOT guarantee US nodes alive
proxyfix detect

# Live group selection
curl -sS --unix-socket /tmp/verge/verge-mihomo.sock http://localhost/proxies \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['proxies'];
print({k:d[k].get('now') for k in ['美国故障转移','香港故障转移','故障转移','us自动切换','自动选择']})"

# US group alive?
curl -sS --unix-socket /tmp/verge/verge-mihomo.sock \
  "http://localhost/group/$(python3 -c 'import urllib.parse;print(urllib.parse.quote(\"美国故障转移\"))')/delay?timeout=5000&url=http://www.gstatic.com/generate_204"

# Connection chain for a host (open the app, then):
curl -sS --unix-socket /tmp/verge/verge-mihomo.sock http://localhost/connections \
  | python3 -c "import sys,json
for c in json.load(sys.stdin).get('connections') or []:
 m=c.get('metadata') or {}; h=m.get('host') or ''
 if any(x in h for x in ['anthropic','claude','cursor','spotify','opencode']):
  print(h, c.get('rule'), c.get('chains'))"

# Egress country via default MATCH
curl -sS --max-time 10 -x http://127.0.0.1:7897 https://cloudflare.com/cdn-cgi/trace | rg 'ip|loc|colo'
```

## Known failure modes (2026-08-06)

1. **All 极客云 + Dual+Net US nodes `alive: false`** → pure US path hangs TLS-after-handshake or times out. Fixed for usability by degraded `自动选择` third hop; **restore true US when provider recovers** (check 机场 status / refresh subscriptions in Verge).
2. **proxyfix alone is not enough for US outages** — detect checks fake-ip + HTTPS smoke; add group delay check above.
3. **Clash Verge `startup_script` requires a `.sh` path** — `proxyfix fix --quiet` with args is rejected (`unsupported script extension`). Use `~/.local/bin/proxyfix-startup.sh`.
4. Before coordinated multi-file Clash edits: `systemctl --user stop proxyfix.path proxyfix.timer`, then re-enable and run `proxyfix-guard` once.

## Do not

- Put default MATCH on HK (breaks Claude if anything leaks)
- Put Spotify on `自动选择` / US
- Put proxy env vars in `/etc/environment`
- Edit `~/.local/share/omarchy/` for this
