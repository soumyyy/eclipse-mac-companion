#!/usr/bin/env python3
"""Enable the Eclipse Mac Hermes plugin in a Hermes config.yaml."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import shutil
import sys

import yaml


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".hermes" / "config.yaml"
    backup = path.with_name(
        f"config.yaml.eclipse-mac-backup-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    )
    shutil.copy2(path, backup)

    config = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    plugins = config.setdefault("plugins", {})
    enabled = plugins.get("enabled")
    if not isinstance(enabled, list):
        enabled = []
    if "eclipse-mac" not in enabled:
        enabled.append("eclipse-mac")
    plugins["enabled"] = sorted(enabled)

    disabled = plugins.get("disabled")
    if isinstance(disabled, list):
        plugins["disabled"] = sorted(item for item in disabled if item != "eclipse-mac")

    platform_toolsets = config.setdefault("platform_toolsets", {})
    cli_toolsets = platform_toolsets.get("cli")
    if not isinstance(cli_toolsets, list):
        cli_toolsets = []
    if "eclipse-mac" not in cli_toolsets:
        cli_toolsets.append("eclipse-mac")
    platform_toolsets["cli"] = cli_toolsets

    path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
    print(f"updated {path}")
    print(f"backup {backup}")
    print(f"plugins.enabled contains eclipse-mac: {'eclipse-mac' in plugins['enabled']}")
    print(f"platform_toolsets.cli contains eclipse-mac: {'eclipse-mac' in platform_toolsets['cli']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
