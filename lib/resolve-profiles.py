#!/usr/bin/env python3
"""Resolve the active Clash Verge profile chain into shell assignments.

Clash Verge Rev names every profile file after a generated UID, so the paths
differ on each install. `profiles.yaml` records the active subscription under
`current:` and its enhancement chain under that item's `option:` block, which
is enough to locate the merge/rules/groups/script/proxies files generically.

Emits `KEY=value` lines for `eval`; missing pieces are simply omitted so the
caller can fall back. Only stdlib is used because PyYAML is not a dependency.
"""

from __future__ import annotations

import sys
from pathlib import Path

CHAIN_KEYS = ("merge", "script", "rules", "proxies", "groups")


def parse_profiles(text: str) -> tuple[str | None, list[dict]]:
    """Minimal parser for the flat `current:` / `items:` shape Verge writes."""
    current: str | None = None
    items: list[dict] = []
    item: dict | None = None
    in_option = False

    for raw in text.splitlines():
        if raw.startswith("current:"):
            current = raw.split(":", 1)[1].strip().strip("'\"") or None
            continue

        if raw.startswith("- "):
            item = {}
            items.append(item)
            in_option = False
            raw = "  " + raw[2:]

        if item is None or not raw.strip() or raw.lstrip().startswith("#"):
            continue

        indent = len(raw) - len(raw.lstrip())
        key, _, value = raw.strip().partition(":")
        value = value.strip().strip("'\"")

        if indent == 2:
            in_option = key == "option"
            if not in_option:
                item[key] = value
        elif indent >= 4 and in_option and key in CHAIN_KEYS:
            item.setdefault("option", {})[key] = value

    return current, items


def main() -> int:
    clash_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if clash_dir is None:
        print("usage: resolve-profiles.py CLASH_DIR", file=sys.stderr)
        return 2

    profiles = clash_dir / "profiles.yaml"
    if not profiles.exists():
        return 1

    try:
        current, items = parse_profiles(profiles.read_text(encoding="utf-8"))
    except OSError:
        return 1

    by_uid = {i["uid"]: i for i in items if i.get("uid")}
    active = by_uid.get(current or "")
    out: dict[str, str] = {}

    if active:
        out["PROXYFIX_CURRENT_PROFILE"] = active.get("file", "")
        for key, uid in (active.get("option") or {}).items():
            target = by_uid.get(uid)
            if target and target.get("file"):
                out[f"PROXYFIX_{key.upper()}_PROFILE"] = target["file"]

    # Every remote subscription is worth snapshotting, not just the active one:
    # a background update to an inactive profile can still break the runtime.
    remotes = [i["file"] for i in items if i.get("type") == "remote" and i.get("file")]
    if remotes:
        out["PROXYFIX_REMOTE_PROFILES"] = " ".join(remotes)

    if not out:
        return 1

    for key, value in out.items():
        if value:
            print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
