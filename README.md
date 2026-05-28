# Proxyfix

Unified Clash TUN fake-ip proxy detect & fix for Arch + Omarchy + Clash Verge.

## Quick start

```bash
# From repo
./proxyfix fix

# After install
proxyfix fix
proxyfix detect
proxyfix status
```

## What it fixes

- Clash merge profile `fake-ip-filter` and DIRECT `prepend-rules` (Cursor, Steam, Discord, pacman, HuggingFace, etc.)
- Clash localhost security (`allow-lan: false`)
- Shell proxy via `~/.config/omarchy/proxy.sh`
- Cursor `settings.json` and `~/.config/electron-flags.conf`
- Auto-runs after Clash config changes (systemd path + timer)
- Auto-runs on Clash Verge startup and `omarchy update`

## Install

```bash
./install.sh
```

Installs:

- `~/.local/bin/proxyfix` → this repo
- systemd user units: `proxyfix.path`, `proxyfix.service`, `proxyfix.timer`
- Clash Verge `startup_script` in `verge.yaml`

## Commands

| Command | Purpose |
|---------|---------|
| `proxyfix fix` | Detect and repair all layers |
| `proxyfix detect` | Check only; exit 1 if broken |
| `proxyfix status` | Report + shell proxy status |
| `proxyfix test` | HTTPS smoke tests |
| `proxyfix download URL [out]` | Direct-first for large CDN files |
| `proxyfix fix --app steam` | Limit to one app group |

## Large downloads

Domains in `manifests/apps.yaml` → `direct_large_suffixes` (Steam CDN, HuggingFace, LM Studio, etc.) try **DIRECT** first for files ≥ 50 MB. Falls back to Clash mixed port if direct fails.

Pacman always uses proxy (required for geo mirror routing).

## Auto triggers

1. **systemd path** — watches Clash config/profile files
2. **systemd timer** — every 10 minutes
3. **Clash Verge startup_script**
4. **omarchy post-update hook**

## Verification

```bash
proxyfix detect && echo OK
getent ahosts api2.cursor.sh store.steampowered.com
systemctl --user status proxyfix.path proxyfix.timer
journalctl --user -t proxyfix -n 10
```

After Cursor fixes: **fully quit Cursor** and reopen via `cursor-launch`.

## Related

- `cursor-tools fix-all` — delegates to `proxyfix fix` + folder-sort + network test
- Hermes note: `04 Tech/Hermes/proxyfix.md`
