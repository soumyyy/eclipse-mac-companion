"""Hermes plugin for Eclipse Mac bridge tools.

This plugin keeps Hermes' model-facing surface native while delegating all Mac
execution to the bridge and Mac app policy layer. Hermes invokes these tools;
the plugin shells out to the deployed JSON tool host on the same VPS.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


TOOLSET = "eclipse-mac"
DEFAULT_BRIDGE_URL = "http://127.0.0.1:8765"
DEFAULT_TOOL_HOST = "/home/openclaw/eclipse-mac-bridge/hermes_tool_host.py"
DEFAULT_TOKEN_FILE = "/home/openclaw/eclipse-mac-bridge/.bridge-token"
DEFAULT_DEVICE_ID = "mac_soumya_local"

TOOL_MAP = {
    "eclipse_mac_get_active_window": "mac.get_active_window",
    "eclipse_mac_capture_window": "mac.capture_window",
    "eclipse_mac_show_notification": "mac.show_notification",
    "eclipse_mac_type_text": "mac.type_text",
    "eclipse_mac_press_key": "mac.press_key",
    "eclipse_mac_click_element": "mac.click_element",
}


def register(ctx: Any) -> None:
    for name, hermes_tool in TOOL_MAP.items():
        ctx.register_tool(
            name=name,
            toolset=TOOLSET,
            schema=schema_for(name),
            handler=lambda args, _tool=hermes_tool, **kw: invoke_tool(_tool, args or {}),
            check_fn=check_requirements,
            description=schema_for(name)["description"],
            emoji="🖥️",
        )

    ctx.register_tool(
        name="eclipse_mac_list_devices",
        toolset=TOOLSET,
        schema={
            "name": "eclipse_mac_list_devices",
            "description": "List Eclipse Mac worker devices that have posted bridge heartbeats.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "properties": {},
            },
        },
        handler=lambda args, **kw: run_host(["devices"]),
        check_fn=check_requirements,
        description="List Eclipse Mac worker devices that have posted bridge heartbeats.",
        emoji="🖥️",
    )


def schema_for(name: str) -> dict[str, Any]:
    common_controls = {
        "wait": {
            "type": "boolean",
            "description": "Wait for the Mac result instead of returning immediately after queueing.",
        },
        "timeout_seconds": {
            "type": "number",
            "minimum": 0.1,
            "maximum": 300,
            "description": "Maximum time to wait when wait is true.",
        },
    }
    if name == "eclipse_mac_get_active_window":
        return {
            "name": name,
            "description": "Get the active app/window context from the Eclipse Mac worker. Read-only and waits by default.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "properties": common_controls,
            },
        }
    if name == "eclipse_mac_capture_window":
        return {
            "name": name,
            "description": "Capture metadata for the active Mac window through the Eclipse Mac worker. Read-only and waits by default.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "properties": common_controls,
            },
        }
    if name == "eclipse_mac_show_notification":
        return {
            "name": name,
            "description": "Ask Eclipse Mac to show a local notification.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "required": ["title"],
                "properties": {
                    "title": {"type": "string", "minLength": 1},
                    "body": {"type": "string"},
                    **common_controls,
                },
            },
        }
    if name == "eclipse_mac_type_text":
        return {
            "name": name,
            "description": "Request Mac-side approval to type text into the currently focused editable field.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "required": ["text"],
                "properties": {
                    "text": {"type": "string", "minLength": 1},
                    **common_controls,
                },
            },
        }
    if name == "eclipse_mac_press_key":
        return {
            "name": name,
            "description": "Request Mac-side approval to press an allowed key such as escape, return, tab, space, or arrow keys.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "required": ["key"],
                "properties": {
                    "key": {"type": "string", "minLength": 1},
                    "modifiers": {
                        "type": "array",
                        "items": {"enum": ["command", "option", "control", "shift"]},
                    },
                    **common_controls,
                },
            },
        }
    if name == "eclipse_mac_click_element":
        return {
            "name": name,
            "description": "Request Mac-side approval to click an Accessibility element by exact role and optional exact label.",
            "parameters": {
                "type": "object",
                "additionalProperties": False,
                "required": ["element_role"],
                "properties": {
                    "element_role": {"type": "string", "minLength": 1},
                    "element_label": {"type": "string"},
                    **common_controls,
                },
            },
        }
    raise ValueError(f"Unknown Eclipse Mac tool schema: {name}")


def invoke_tool(tool_name: str, args: dict[str, Any]) -> str:
    wait = args.pop("wait", None)
    timeout_seconds = args.pop("timeout_seconds", None)
    command = ["call", tool_name, "--arguments", json.dumps(args, separators=(",", ":"))]
    if wait is True:
        command.append("--wait")
    elif wait is False:
        command.append("--no-wait")
    if timeout_seconds is not None:
        command.extend(["--timeout-seconds", str(timeout_seconds)])
    return run_host(command)


def run_host(command: list[str], global_options: list[str] | None = None) -> str:
    host = os.environ.get("ECLIPSE_MAC_TOOL_HOST", DEFAULT_TOOL_HOST)
    bridge_url = os.environ.get("ECLIPSE_BRIDGE_URL", DEFAULT_BRIDGE_URL)
    device_id = os.environ.get("ECLIPSE_MAC_DEVICE_ID", DEFAULT_DEVICE_ID)
    token = os.environ.get("ECLIPSE_BRIDGE_TOKEN") or read_token()

    full_command = [
        sys.executable,
        host,
        "--url",
        bridge_url,
        "--device-id",
        device_id,
    ]
    if token:
        full_command.extend(["--token", token])
    full_command.extend(global_options or [])
    full_command.extend(command)

    completed = subprocess.run(
        full_command,
        capture_output=True,
        text=True,
        timeout=330,
        check=False,
    )
    if completed.returncode != 0:
        return json.dumps({
            "error": {
                "code": "eclipse_mac_tool_error",
                "message": (completed.stderr or completed.stdout or "Eclipse Mac tool host failed").strip()[:2000],
            }
        })
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        parsed = {"raw": completed.stdout.strip()}
    return json.dumps(parsed, sort_keys=True, separators=(",", ":"))


def read_token() -> str:
    token_file = Path(os.environ.get("ECLIPSE_BRIDGE_TOKEN_FILE", DEFAULT_TOKEN_FILE))
    try:
        return token_file.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def check_requirements() -> bool:
    host = Path(os.environ.get("ECLIPSE_MAC_TOOL_HOST", DEFAULT_TOOL_HOST))
    return host.exists() and bool(os.environ.get("ECLIPSE_BRIDGE_TOKEN") or read_token())
