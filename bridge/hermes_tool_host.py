#!/usr/bin/env python3
"""JSON-in/JSON-out Hermes tool host for Eclipse Mac.

This executable is intentionally small and process-oriented. Hermes or another
agent host can shell out to list available Mac tools or invoke one tool call.
The adapter still talks only to the bridge; the Mac app remains the execution
and approval authority.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from hermes_adapter import EclipseMacHermesAdapter


def main() -> int:
    parser = argparse.ArgumentParser(description="Expose Eclipse Mac bridge tools as JSON commands.")
    parser.add_argument("--url", help="Bridge URL. Defaults to ECLIPSE_BRIDGE_URL or localhost.")
    parser.add_argument("--token", help="Bridge bearer token. Defaults to ECLIPSE_BRIDGE_TOKEN.")
    parser.add_argument("--device-id", help="Mac device ID. Defaults to ECLIPSE_MAC_DEVICE_ID.")
    parser.add_argument("--timeout-seconds", type=float, default=30)
    parser.add_argument("--pretty", action="store_true")

    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("list-tools", help="List tool metadata.")
    subparsers.add_parser("devices", help="List devices with recent bridge heartbeats.")
    subparsers.add_parser("heartbeat", help="Post a heartbeat for this host/device.")

    call_parser = subparsers.add_parser("call", help="Invoke a single tool.")
    call_parser.add_argument("tool_name")
    call_parser.add_argument(
        "--arguments",
        help="JSON object for tool arguments. If omitted, stdin is read when non-empty.",
    )
    call_parser.add_argument("--wait", action="store_true", help="Wait for the Mac result.")
    call_parser.add_argument("--no-wait", action="store_true", help="Return after queueing.")
    call_parser.add_argument("--no-cancel-on-timeout", action="store_true")

    args = parser.parse_args()
    adapter = EclipseMacHermesAdapter(
        bridge_url=args.url,
        token=args.token,
        device_id=args.device_id,
        timeout_seconds=args.timeout_seconds,
    )

    try:
        if args.command == "list-tools":
            output: dict[str, Any] = {"tools": adapter.list_tools()}
        elif args.command == "devices":
            output = adapter.list_devices()
        elif args.command == "heartbeat":
            output = adapter.post_heartbeat(status="online", app_version="hermes-tool-host")
        elif args.command == "call":
            wait = None
            if args.wait and args.no_wait:
                raise ValueError("--wait and --no-wait conflict")
            if args.wait:
                wait = True
            elif args.no_wait:
                wait = False
            output = adapter.invoke_tool(
                args.tool_name,
                arguments=read_arguments(args.arguments),
                wait=wait,
                timeout_seconds=args.timeout_seconds,
                cancel_on_timeout=not args.no_cancel_on_timeout,
            )
        else:
            raise ValueError(f"Unsupported command: {args.command}")
    except Exception as error:
        print_json({"error": {"code": "hermes_tool_host_error", "message": str(error)}}, pretty=args.pretty, stream=sys.stderr)
        return 1

    print_json(output, pretty=args.pretty)
    return 0


def read_arguments(raw: str | None) -> dict[str, Any]:
    if raw is None:
        stdin = sys.stdin.read()
        raw = stdin if stdin.strip() else "{}"
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("Tool arguments must be a JSON object")
    return value


def print_json(value: dict[str, Any], *, pretty: bool, stream: Any = sys.stdout) -> None:
    if pretty:
        print(json.dumps(value, indent=2, sort_keys=True), file=stream)
    else:
        print(json.dumps(value, sort_keys=True, separators=(",", ":")), file=stream)


if __name__ == "__main__":
    raise SystemExit(main())
