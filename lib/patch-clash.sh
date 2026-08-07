#!/usr/bin/env bash
# Patch Clash merge + runtime configs from manifests/apps.yaml
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

APP_FILTER="${1:-all}"

MERGE_PROFILE=$(merge_profile_path)
RULES_PROFILE=$(rules_profile_path || true)

_patched=0
python3 - "$MANIFEST" "$APP_FILTER" "$CLASH_DIR" "$MERGE_PROFILE" "$RULES_PROFILE" <<'PY' || _patched=$?
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
app_filter = sys.argv[2]
clash_dir = Path(sys.argv[3])
merge_profile = Path(sys.argv[4]) if sys.argv[4] else None
rules_profile = Path(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else None


def load_manifest(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    data = {
        "fake_ip_filter": [],
        "direct_prepend_rules": [],
    }
    key = None
    for line in text.splitlines():
        m = re.match(r"^(\w+):\s*$", line)
        if m and m.group(1) in ("fake_ip_filter", "direct_prepend_rules"):
            key = m.group(1)
            continue
        if key and re.match(r"^\s+-\s+", line):
            val = line.strip()[2:].strip()
            if val.startswith("#"):
                continue
            data[key].append(val.strip("'\""))
            continue
        if line and not line.startswith(" ") and not line.startswith("#"):
            key = None
    # Parse apps section for per-app filter
    apps = {}
    in_apps = False
    current_app = None
    app_key = None
    for line in text.splitlines():
        if line.strip() == "apps:":
            in_apps = True
            continue
        if not in_apps:
            continue
        if re.match(r"^  \w+:\s*$", line):
            current_app = line.strip()[:-1]
            apps[current_app] = {"fake_ip_filter": [], "direct_prepend_rules": []}
            app_key = None
            continue
        if current_app and re.match(r"^    (\w+):\s*$", line):
            app_key = line.strip().split(":")[0]
            continue
        if current_app and app_key and re.match(r"^      -\s+", line):
            val = line.strip()[2:].strip().strip("'\"")
            apps[current_app].setdefault(app_key, []).append(val)
            continue
        if line.startswith("download:") or line.startswith("probe_hosts:"):
            break
    data["apps"] = apps
    return data


def domains_for_filter(data: dict, app_filter: str) -> tuple[list, list]:
    fake, direct = list(data["fake_ip_filter"]), list(data["direct_prepend_rules"])
    if app_filter == "all":
        return fake, direct
    app = data.get("apps", {}).get(app_filter, {})
    if app.get("fake_ip_filter"):
        fake = app["fake_ip_filter"]
    if app.get("direct_prepend_rules"):
        direct = app["direct_prepend_rules"]
    elif app_filter in ("cursor", "discord", "pacman", "ticktick", "anki"):
        direct = []
    return fake, direct


def patch_fake_ip_filter(path: Path, domains: list) -> bool:
    if not path.exists() or not domains:
        return False
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    out, i, changed = [], 0, False
    while i < len(lines):
        line = lines[i]
        if line.strip() == "fake-ip-filter:":
            indent = line[: len(line) - len(line.lstrip())]
            item_indent = indent + "  "
            out.append(line)
            i += 1
            existing, block = set(), []
            while i < len(lines):
                nxt = lines[i]
                if nxt.startswith(item_indent + "- "):
                    val = nxt.strip()[2:].strip("'\"")
                    existing.add(val)
                    block.append(nxt)
                    i += 1
                elif nxt.startswith(indent + "- ") and not nxt.startswith(item_indent):
                    val = nxt[len(indent) :].strip()[2:].strip("'\"")
                    existing.add(val)
                    block.append(item_indent + nxt[len(indent) :].lstrip())
                    changed = True
                    i += 1
                else:
                    break
            for d in domains:
                if d not in existing:
                    block.append(f"{item_indent}- '{d}'")
                    changed = True
            out.extend(block)
            continue
        out.append(line)
        i += 1
    if changed:
        path.write_text("\n".join(out) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
        print(f"PATCHED fake-ip-filter: {path}")
    else:
        print(f"OK fake-ip-filter: {path}")
    return changed


def patch_prepend_rules(path: Path, rules: list) -> bool:
    if not path.exists() or not rules:
        return False
    text = path.read_text(encoding="utf-8")
    if "prepend-rules:" not in text:
        # Insert prepend-rules block after fake-ip-filter section or at end
        block = "prepend-rules:\n" + "\n".join(f"  - {r}" for r in rules) + "\n"
        path.write_text(text.rstrip() + "\n" + block, encoding="utf-8")
        print(f"ADDED prepend-rules: {path}")
        return True
    lines = text.splitlines()
    out, i, changed = [], 0, False
    while i < len(lines):
        line = lines[i]
        if line.strip() == "prepend-rules:":
            indent = line[: len(line) - len(line.lstrip())]
            item_indent = indent + "  "
            out.append(line)
            i += 1
            existing, block = set(), []
            while i < len(lines):
                nxt = lines[i]
                if nxt.startswith(item_indent + "- ") or (
                    nxt.startswith("- ") and line.strip() == "prepend-rules:"
                ):
                    val = nxt.split("- ", 1)[1].strip() if "- " in nxt else nxt.strip()
                    existing.add(val)
                    block.append(nxt if nxt.startswith(item_indent) else item_indent + nxt.lstrip())
                    i += 1
                elif nxt.startswith("- "):
                    val = nxt.split("- ", 1)[1].strip()
                    existing.add(val)
                    block.append(nxt)
                    i += 1
                else:
                    break
            for r in rules:
                if r not in existing:
                    block.insert(0, f"{item_indent}- {r}")
                    changed = True
            out.extend(block)
            continue
        out.append(line)
        i += 1
    if changed:
        path.write_text("\n".join(out) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
        print(f"PATCHED prepend-rules: {path}")
    else:
        print(f"OK prepend-rules: {path}")
    return changed


def patch_runtime_rules(path: Path, rules: list) -> bool:
    """Prepend DIRECT rules to active `rules:` — mihomo ignores merge `prepend-rules` on API reload."""
    if not path.exists() or not rules:
        return False
    text = path.read_text(encoding="utf-8")
    if "rules:" not in text:
        return False
    lines = text.splitlines()
    out, i, changed = [], 0, False
    while i < len(lines):
        line = lines[i]
        if line.strip() == "rules:":
            out.append(line)
            i += 1
            existing, block = set(), []
            while i < len(lines):
                nxt = lines[i]
                if nxt.startswith("- "):
                    val = nxt.split("- ", 1)[1].strip()
                    existing.add(val)
                    block.append(nxt)
                    i += 1
                else:
                    break
            for r in reversed(rules):
                if r not in existing:
                    block.insert(0, f"- {r}")
                    changed = True
            out.extend(block)
            continue
        out.append(line)
        i += 1
    if changed:
        path.write_text("\n".join(out) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
        print(f"PATCHED runtime rules: {path}")
    else:
        print(f"OK runtime rules: {path}")
    return changed


def patch_rules_profile(path: Path, rules: list) -> bool:
    """Patch Clash Verge rules enhancement `prepend:` list."""
    if not path.exists() or not rules:
        return False
    text = path.read_text(encoding="utf-8")
    if "prepend:" not in text:
        return False
    if re.search(r"^prepend:\s*\[\]\s*$", text, re.MULTILINE):
        block = "prepend:\n" + "\n".join(f"  - {r}" for r in rules) + "\n"
        text = re.sub(r"^prepend:\s*\[\]\s*$", block.rstrip(), text, count=1, flags=re.MULTILINE)
        path.write_text(text, encoding="utf-8")
        print(f"PATCHED rules profile prepend: {path}")
        return True
    lines = text.splitlines()
    out, i, changed = [], 0, False
    while i < len(lines):
        line = lines[i]
        if line.strip() == "prepend:":
            out.append(line)
            i += 1
            existing, block = set(), []
            while i < len(lines):
                nxt = lines[i]
                if re.match(r"^\s+-\s+", nxt):
                    val = nxt.split("- ", 1)[1].strip()
                    existing.add(val)
                    block.append(nxt)
                    i += 1
                else:
                    break
            for r in reversed(rules):
                if r not in existing:
                    block.insert(0, f"  - {r}")
                    changed = True
            out.extend(block)
            continue
        out.append(line)
        i += 1
    if changed:
        path.write_text("\n".join(out) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
        print(f"PATCHED rules profile prepend: {path}")
    else:
        print(f"OK rules profile prepend: {path}")
    return changed


data = load_manifest(manifest_path)
fake_domains, direct_rules = domains_for_filter(data, app_filter)
targets = [clash_dir / "clash-verge.yaml", clash_dir / "dns_config.yaml"]
if merge_profile is not None:
    targets.insert(0, merge_profile)
runtime = clash_dir / "clash-verge.yaml"

any_changed = False
for t in targets:
    if patch_fake_ip_filter(t, fake_domains):
        any_changed = True
    if app_filter in ("all", "steam", "strava", "pacman") and patch_prepend_rules(t, direct_rules):
        any_changed = True

if direct_rules and patch_runtime_rules(runtime, direct_rules):
    any_changed = True

if direct_rules and rules_profile is not None and patch_rules_profile(rules_profile, direct_rules):
    any_changed = True

sys.exit(0 if any_changed else 1)
PY

if (( _patched == 0 )); then
  if reload_mihomo; then
    ok "mihomo config reloaded"
  else
    warn "mihomo reload failed — restart Clash Verge if apps still broken"
  fi
fi
# Avoid polkit fingerprint prompts from systemd user timers (QUIET=1).
# NOTE: trailing || true — with QUIET=1 the && list would return 1 and,
# as the script's last command, make systemd runs exit 1 despite success.
[[ -z ${QUIET:-} ]] && flush_dns || true
