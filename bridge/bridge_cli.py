#!/usr/bin/env python3
"""Operator CLI for the Eclipse Mac development bridge."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def main() -> int:
    parser = argparse.ArgumentParser(description="Operate an Eclipse Mac bridge.")
    parser.add_argument(
        "--url",
        default=os.environ.get("ECLIPSE_BRIDGE_URL", "http://127.0.0.1:8765"),
        help="Bridge base URL. Defaults to ECLIPSE_BRIDGE_URL or localhost.",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("ECLIPSE_BRIDGE_TOKEN", ""),
        help="Bearer token. Defaults to ECLIPSE_BRIDGE_TOKEN.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON responses.",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("health", help="Check bridge health.")
    subparsers.add_parser("stats", help="Show queued job/result counts.")
    subparsers.add_parser("jobs", help="List queued jobs without consuming them.")
    subparsers.add_parser("results", help="List stored results.")

    result_parser = subparsers.add_parser("result", help="Fetch one result by job ID.")
    result_parser.add_argument("job_id")

    context_parser = subparsers.add_parser("create-context", help="Queue context.get_active_window.")
    add_common_job_args(context_parser)

    text_parser = subparsers.add_parser("create-set-text", help="Queue ui.set_text.")
    add_common_job_args(text_parser)
    text_parser.add_argument("text", help="Text to request after Mac-side approval.")

    raw_parser = subparsers.add_parser("create-job", help="Queue a raw job JSON file.")
    raw_parser.add_argument("path", help="Path to JSON job/create request.")

    args = parser.parse_args()

    try:
        response = dispatch(args)
    except HTTPError as error:
        body = error.read().decode("utf-8")
        print(body or f"HTTP {error.code}", file=sys.stderr)
        return 1
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1

    if response is not None:
        print_json(response, pretty=args.pretty)
    return 0


def add_common_job_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--device-id", default="mac_soumya_local")
    parser.add_argument("--ttl-seconds", type=int, default=30)
    parser.add_argument("--idempotency-key")


def dispatch(args: argparse.Namespace) -> dict[str, Any] | None:
    if args.command == "health":
        return request_json(args, "GET", "/health", auth=False)
    if args.command == "stats":
        return request_json(args, "GET", "/stats")
    if args.command == "jobs":
        return request_json(args, "GET", "/jobs")
    if args.command == "results":
        return request_json(args, "GET", "/results")
    if args.command == "result":
        return request_json(args, "GET", f"/results/{args.job_id}")
    if args.command == "create-context":
        return request_json(args, "POST", "/jobs", body=job_body(
            args,
            kind="context.get_active_window",
            risk="read",
            input_body={},
        ))
    if args.command == "create-set-text":
        return request_json(args, "POST", "/jobs", body=job_body(
            args,
            kind="ui.set_text",
            risk="reversible",
            input_body={"text": args.text},
        ))
    if args.command == "create-job":
        with open(args.path, "r", encoding="utf-8") as handle:
            body = json.load(handle)
        return request_json(args, "POST", "/jobs", body=body)
    raise ValueError(f"Unsupported command: {args.command}")


def job_body(
    args: argparse.Namespace,
    *,
    kind: str,
    risk: str,
    input_body: dict[str, Any],
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "device_id": args.device_id,
        "kind": kind,
        "risk": risk,
        "input": input_body,
        "ttl_seconds": args.ttl_seconds,
    }
    if args.idempotency_key:
        body["idempotency_key"] = args.idempotency_key
    return body


def request_json(
    args: argparse.Namespace,
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    query: dict[str, str] | None = None,
    auth: bool = True,
) -> dict[str, Any] | None:
    url = args.url.rstrip("/") + path
    if query:
        url += "?" + urlencode(query)
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {
        "accept": "application/json",
        "user-agent": "EclipseMacBridgeCLI/0.1",
    }
    if body is not None:
        headers["content-type"] = "application/json"
    if auth and args.token:
        headers["authorization"] = f"Bearer {args.token}"

    request = Request(url, data=data, headers=headers, method=method)
    with urlopen(request, timeout=10) as response:
        raw = response.read()
    if not raw:
        return None
    return json.loads(raw.decode("utf-8"))


def print_json(value: dict[str, Any], *, pretty: bool) -> None:
    if pretty:
        print(json.dumps(value, indent=2, sort_keys=True))
    else:
        print(json.dumps(value, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    raise SystemExit(main())
