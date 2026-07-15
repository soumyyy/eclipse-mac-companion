#!/usr/bin/env python3
"""Local development bridge for Eclipse Mac.

This is intentionally dependency-light. It is not the production VPS bridge; it
only gives the Mac app and tests a local HTTP transport that speaks the shared
job/result envelopes.
"""

from __future__ import annotations

import argparse
import json
import os
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

PROTOCOL_VERSION = "0.1"
JOB_KINDS = {"context.get_active_window", "ui.set_text"}
RISKS = {"read", "reversible", "consequential"}
STATUSES = {"succeeded", "failed", "rejected", "expired", "pending_approval"}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def isoformat(value: datetime) -> str:
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def prefixed_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


@dataclass
class BridgeState:
    jobs: list[dict[str, Any]] = field(default_factory=list)
    results_by_job_id: dict[str, dict[str, Any]] = field(default_factory=dict)
    results_by_idempotency_key: dict[str, dict[str, Any]] = field(default_factory=dict)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def create_job(self, request: dict[str, Any]) -> dict[str, Any]:
        if "job_id" in request:
            job = dict(request)
        else:
            ttl_seconds = int(request.get("ttl_seconds", 30))
            job = {
                "job_id": prefixed_id("job"),
                "protocol_version": PROTOCOL_VERSION,
                "device_id": request.get("device_id", "mac_soumya_local"),
                "kind": request["kind"],
                "risk": request["risk"],
                "input": request.get("input", {}),
                "expires_at": isoformat(utc_now() + timedelta(seconds=ttl_seconds)),
                "idempotency_key": request.get("idempotency_key", prefixed_id("idem")),
            }

        validate_job(job)
        with self.lock:
            self.jobs.append(job)
        return job

    def next_job(self, device_id: str | None) -> dict[str, Any] | None:
        with self.lock:
            for index, job in enumerate(self.jobs):
                if device_id is None or job["device_id"] == device_id:
                    return self.jobs.pop(index)
        return None

    def save_result(self, result: dict[str, Any]) -> tuple[dict[str, Any], bool]:
        validate_result(result)
        with self.lock:
            existing = self.results_by_idempotency_key.get(result["idempotency_key"])
            if existing is not None:
                return existing, True
            self.results_by_job_id[result["job_id"]] = result
            self.results_by_idempotency_key[result["idempotency_key"]] = result
            return result, False

    def result(self, job_id: str) -> dict[str, Any] | None:
        with self.lock:
            return self.results_by_job_id.get(job_id)

    def all_results(self) -> list[dict[str, Any]]:
        with self.lock:
            return list(self.results_by_job_id.values())


def validate_job(job: dict[str, Any]) -> None:
    required = {
        "job_id",
        "protocol_version",
        "device_id",
        "kind",
        "risk",
        "input",
        "expires_at",
        "idempotency_key",
    }
    missing = required - job.keys()
    if missing:
        raise ValueError(f"job missing fields: {', '.join(sorted(missing))}")
    if job["protocol_version"] != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol_version")
    if job["kind"] not in JOB_KINDS:
        raise ValueError("unsupported job kind")
    if job["risk"] not in RISKS:
        raise ValueError("unsupported risk")
    if job["kind"] == "context.get_active_window" and job["risk"] != "read":
        raise ValueError("context.get_active_window requires read risk")
    if job["kind"] == "ui.set_text":
        if job["risk"] != "reversible":
            raise ValueError("ui.set_text requires reversible risk")
        text = job.get("input", {}).get("text")
        if not isinstance(text, str) or not text:
            raise ValueError("ui.set_text requires input.text")


def validate_result(result: dict[str, Any]) -> None:
    required = {
        "job_id",
        "protocol_version",
        "device_id",
        "status",
        "completed_at",
        "idempotency_key",
    }
    missing = required - result.keys()
    if missing:
        raise ValueError(f"result missing fields: {', '.join(sorted(missing))}")
    if result["protocol_version"] != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol_version")
    if result["status"] not in STATUSES:
        raise ValueError("unsupported status")


class BridgeHandler(BaseHTTPRequestHandler):
    server: "BridgeHTTPServer"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.respond({
                "ok": True,
                "protocol_version": PROTOCOL_VERSION,
                "auth_required": self.server.token is not None,
            })
            return
        if not self.authorized():
            self.auth_error()
            return
        if parsed.path == "/jobs/next":
            query = parse_qs(parsed.query)
            device_id = query.get("device_id", [None])[0]
            job = self.server.state.next_job(device_id)
            if job is None:
                self.send_response(204)
                self.end_headers()
                return
            self.respond(job)
            return
        if parsed.path == "/results":
            self.respond({"results": self.server.state.all_results()})
            return
        if parsed.path.startswith("/results/"):
            job_id = parsed.path.rsplit("/", 1)[-1]
            result = self.server.state.result(job_id)
            if result is None:
                self.error(404, "result not found")
                return
            self.respond(result)
            return
        self.error(404, "not found")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if not self.authorized():
            self.auth_error()
            return
        try:
            body = self.read_json()
            if parsed.path == "/jobs":
                job = self.server.state.create_job(body)
                self.respond(job, status=201)
                return
            if parsed.path == "/results":
                result, duplicate = self.server.state.save_result(body)
                self.respond({"duplicate": duplicate, "result": result})
                return
            if parsed.path == "/outbox/replay":
                accepted = 0
                duplicates = 0
                stored: list[dict[str, Any]] = []
                for result_body in body.get("results", []):
                    result, duplicate = self.server.state.save_result(result_body)
                    accepted += 0 if duplicate else 1
                    duplicates += 1 if duplicate else 0
                    stored.append(result)
                self.respond({
                    "accepted": accepted,
                    "duplicates": duplicates,
                    "results": stored,
                })
                return
            self.error(404, "not found")
        except ValueError as exc:
            self.error(400, str(exc))

    def read_json(self) -> dict[str, Any]:
        content_length = int(self.headers.get("content-length", "0"))
        raw = self.rfile.read(content_length)
        if not raw:
            return {}
        value = json.loads(raw.decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("request body must be a JSON object")
        return value

    def respond(self, body: dict[str, Any], status: int = 200) -> None:
        encoded = json.dumps(body, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def error(self, status: int, message: str) -> None:
        self.respond({"error": {"code": "mock_bridge_error", "message": message}}, status=status)

    def authorized(self) -> bool:
        if self.server.token is None:
            return True
        return self.headers.get("authorization") == f"Bearer {self.server.token}"

    def auth_error(self) -> None:
        self.send_response(401)
        self.send_header("www-authenticate", "Bearer")
        body = {"error": {"code": "unauthorized", "message": "missing or invalid bearer token"}}
        encoded = json.dumps(body, sort_keys=True).encode("utf-8")
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: Any) -> None:
        return


class BridgeHTTPServer(ThreadingHTTPServer):
    def __init__(
        self,
        address: tuple[str, int],
        state: BridgeState | None = None,
        token: str | None = None,
    ):
        super().__init__(address, BridgeHandler)
        self.state = state or BridgeState()
        self.token = token


def make_server(
    host: str = "127.0.0.1",
    port: int = 8765,
    token: str | None = None,
) -> BridgeHTTPServer:
    return BridgeHTTPServer((host, port), token=token)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the local Eclipse Mac mock bridge.")
    parser.add_argument("--host", default=os.environ.get("ECLIPSE_BRIDGE_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("ECLIPSE_BRIDGE_PORT", "8765")))
    parser.add_argument(
        "--token",
        default=os.environ.get("ECLIPSE_BRIDGE_TOKEN"),
        help="Optional bearer token. Also read from ECLIPSE_BRIDGE_TOKEN.",
    )
    args = parser.parse_args()

    server = make_server(args.host, args.port, token=args.token)
    auth = " with bearer auth" if args.token else ""
    print(f"mock bridge listening on http://{args.host}:{args.port}{auth}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
