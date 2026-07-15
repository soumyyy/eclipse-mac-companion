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
import sqlite3
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

PROTOCOL_VERSION = "0.1"
JOB_KINDS = {
    "context.get_active_window",
    "context.capture_window",
    "notification.show",
    "ui.set_text",
    "ui.press_key",
    "ui.click_element",
}
RISKS = {"read", "reversible", "consequential"}
STATUSES = {"succeeded", "failed", "rejected", "expired", "pending_approval"}
ALLOWED_KEYS = {
    "escape",
    "return",
    "enter",
    "tab",
    "space",
    "arrow_left",
    "arrow_right",
    "arrow_up",
    "arrow_down",
}
ALLOWED_MODIFIERS = {"command", "option", "control", "shift"}


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
    heartbeats_by_device_id: dict[str, dict[str, Any]] = field(default_factory=dict)
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

    def cancel_job(self, job_id: str, message: str = "Job cancelled before delivery") -> tuple[dict[str, Any] | None, bool]:
        with self.lock:
            existing = self.results_by_job_id.get(job_id)
            if existing is not None:
                return existing, False
            for index, job in enumerate(self.jobs):
                if job["job_id"] == job_id:
                    self.jobs.pop(index)
                    result = cancellation_result(job, message=message)
                    self.results_by_job_id[result["job_id"]] = result
                    self.results_by_idempotency_key[result["idempotency_key"]] = result
                    return result, True
        return None, False

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

    def all_jobs(self) -> list[dict[str, Any]]:
        with self.lock:
            return list(self.jobs)

    def save_heartbeat(self, heartbeat: dict[str, Any]) -> dict[str, Any]:
        validate_heartbeat(heartbeat)
        with self.lock:
            self.heartbeats_by_device_id[heartbeat["device_id"]] = heartbeat
        return heartbeat

    def all_devices(self) -> list[dict[str, Any]]:
        with self.lock:
            return sorted(self.heartbeats_by_device_id.values(), key=lambda item: item["device_id"])

    def stats(self) -> dict[str, int]:
        with self.lock:
            return {
                "queued_jobs": len(self.jobs),
                "results": len(self.results_by_job_id),
            }


class SQLiteBridgeState:
    def __init__(self, path: str):
        self.path = path
        self.lock = threading.Lock()
        self._initialize()

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
        with self.lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO jobs (
                    job_id, device_id, idempotency_key, job_json, created_at
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    job["job_id"],
                    job["device_id"],
                    job["idempotency_key"],
                    encode_json(job),
                    isoformat(utc_now()),
                ),
            )
        return job

    def next_job(self, device_id: str | None) -> dict[str, Any] | None:
        with self.lock, self._connect() as connection:
            if device_id is None:
                row = connection.execute(
                    """
                    SELECT id, job_json
                    FROM jobs
                    ORDER BY id
                    LIMIT 1
                    """
                ).fetchone()
            else:
                row = connection.execute(
                    """
                    SELECT id, job_json
                    FROM jobs
                    WHERE device_id = ?
                    ORDER BY id
                    LIMIT 1
                    """,
                    (device_id,),
                ).fetchone()

            if row is None:
                return None
            connection.execute("DELETE FROM jobs WHERE id = ?", (row["id"],))
            return json.loads(row["job_json"])

    def cancel_job(self, job_id: str, message: str = "Job cancelled before delivery") -> tuple[dict[str, Any] | None, bool]:
        with self.lock, self._connect() as connection:
            existing = connection.execute(
                """
                SELECT result_json
                FROM results
                WHERE job_id = ?
                LIMIT 1
                """,
                (job_id,),
            ).fetchone()
            if existing is not None:
                return json.loads(existing["result_json"]), False

            row = connection.execute(
                """
                SELECT id, job_json
                FROM jobs
                WHERE job_id = ?
                LIMIT 1
                """,
                (job_id,),
            ).fetchone()
            if row is None:
                return None, False

            job = json.loads(row["job_json"])
            connection.execute("DELETE FROM jobs WHERE id = ?", (row["id"],))
            result = cancellation_result(job, message=message)
            connection.execute(
                """
                INSERT INTO results (
                    job_id, idempotency_key, result_json, created_at
                ) VALUES (?, ?, ?, ?)
                """,
                (
                    result["job_id"],
                    result["idempotency_key"],
                    encode_json(result),
                    isoformat(utc_now()),
                ),
            )
            return result, True

    def save_result(self, result: dict[str, Any]) -> tuple[dict[str, Any], bool]:
        validate_result(result)
        with self.lock, self._connect() as connection:
            existing = connection.execute(
                """
                SELECT result_json
                FROM results
                WHERE idempotency_key = ?
                LIMIT 1
                """,
                (result["idempotency_key"],),
            ).fetchone()
            if existing is not None:
                return json.loads(existing["result_json"]), True

            connection.execute(
                """
                INSERT INTO results (
                    job_id, idempotency_key, result_json, created_at
                ) VALUES (?, ?, ?, ?)
                """,
                (
                    result["job_id"],
                    result["idempotency_key"],
                    encode_json(result),
                    isoformat(utc_now()),
                ),
            )
            return result, False

    def result(self, job_id: str) -> dict[str, Any] | None:
        with self.lock, self._connect() as connection:
            row = connection.execute(
                """
                SELECT result_json
                FROM results
                WHERE job_id = ?
                LIMIT 1
                """,
                (job_id,),
            ).fetchone()
            return None if row is None else json.loads(row["result_json"])

    def all_results(self) -> list[dict[str, Any]]:
        with self.lock, self._connect() as connection:
            rows = connection.execute(
                """
                SELECT result_json
                FROM results
                ORDER BY id
                """
            ).fetchall()
            return [json.loads(row["result_json"]) for row in rows]

    def all_jobs(self) -> list[dict[str, Any]]:
        with self.lock, self._connect() as connection:
            rows = connection.execute(
                """
                SELECT job_json
                FROM jobs
                ORDER BY id
                """
            ).fetchall()
            return [json.loads(row["job_json"]) for row in rows]

    def save_heartbeat(self, heartbeat: dict[str, Any]) -> dict[str, Any]:
        validate_heartbeat(heartbeat)
        with self.lock, self._connect() as connection:
            connection.execute(
                """
                INSERT INTO heartbeats (
                    device_id, heartbeat_json, updated_at
                ) VALUES (?, ?, ?)
                ON CONFLICT(device_id) DO UPDATE SET
                    heartbeat_json = excluded.heartbeat_json,
                    updated_at = excluded.updated_at
                """,
                (
                    heartbeat["device_id"],
                    encode_json(heartbeat),
                    isoformat(utc_now()),
                ),
            )
        return heartbeat

    def all_devices(self) -> list[dict[str, Any]]:
        with self.lock, self._connect() as connection:
            rows = connection.execute(
                """
                SELECT heartbeat_json
                FROM heartbeats
                ORDER BY device_id
                """
            ).fetchall()
            return [json.loads(row["heartbeat_json"]) for row in rows]

    def stats(self) -> dict[str, int]:
        with self.lock, self._connect() as connection:
            queued_jobs = connection.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]
            results = connection.execute("SELECT COUNT(*) FROM results").fetchone()[0]
            return {
                "queued_jobs": int(queued_jobs),
                "results": int(results),
            }

    def _initialize(self) -> None:
        parent = os.path.dirname(self.path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS jobs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    idempotency_key TEXT NOT NULL,
                    job_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS jobs_device_id_idx
                ON jobs(device_id, id);

                CREATE TABLE IF NOT EXISTS results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_id TEXT NOT NULL UNIQUE,
                    idempotency_key TEXT NOT NULL UNIQUE,
                    result_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS results_job_id_idx
                ON results(job_id);
                CREATE INDEX IF NOT EXISTS results_idempotency_key_idx
                ON results(idempotency_key);

                CREATE TABLE IF NOT EXISTS heartbeats (
                    device_id TEXT NOT NULL PRIMARY KEY,
                    heartbeat_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection


def encode_json(value: dict[str, Any]) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def cancellation_result(job: dict[str, Any], message: str) -> dict[str, Any]:
    return {
        "job_id": job["job_id"],
        "protocol_version": PROTOCOL_VERSION,
        "device_id": job["device_id"],
        "status": "rejected",
        "error": {
            "code": "cancelled_before_delivery",
            "message": message,
        },
        "completed_at": isoformat(utc_now()),
        "idempotency_key": job["idempotency_key"],
    }


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
    if job["kind"] in {"context.get_active_window", "context.capture_window"}:
        if job["risk"] != "read":
            raise ValueError(f"{job['kind']} requires read risk")
        if job.get("input") not in ({}, None):
            raise ValueError(f"{job['kind']} requires empty input")
    elif job["kind"] == "notification.show":
        if job["risk"] != "reversible":
            raise ValueError("notification.show requires reversible risk")
        title = job.get("input", {}).get("title")
        body = job.get("input", {}).get("body")
        if not isinstance(title, str) or not title:
            raise ValueError("notification.show requires input.title")
        if body is not None and not isinstance(body, str):
            raise ValueError("notification.show input.body must be a string")
    elif job["kind"] == "ui.set_text":
        if job["risk"] != "reversible":
            raise ValueError("ui.set_text requires reversible risk")
        text = job.get("input", {}).get("text")
        if not isinstance(text, str) or not text:
            raise ValueError("ui.set_text requires input.text")
    elif job["kind"] == "ui.press_key":
        if job["risk"] != "reversible":
            raise ValueError("ui.press_key requires reversible risk")
        key = job.get("input", {}).get("key")
        if key not in ALLOWED_KEYS:
            raise ValueError("ui.press_key requires an allowed input.key")
        modifiers = job.get("input", {}).get("modifiers", [])
        if not isinstance(modifiers, list) or any(modifier not in ALLOWED_MODIFIERS for modifier in modifiers):
            raise ValueError("ui.press_key input.modifiers contains an unsupported modifier")
    elif job["kind"] == "ui.click_element":
        if job["risk"] != "consequential":
            raise ValueError("ui.click_element requires consequential risk")
        role = job.get("input", {}).get("element_role")
        label = job.get("input", {}).get("element_label")
        if not isinstance(role, str) or not role:
            raise ValueError("ui.click_element requires input.element_role")
        if label is not None and not isinstance(label, str):
            raise ValueError("ui.click_element input.element_label must be a string")


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


def validate_heartbeat(heartbeat: dict[str, Any]) -> None:
    required = {
        "protocol_version",
        "device_id",
        "sent_at",
        "capabilities",
    }
    missing = required - heartbeat.keys()
    if missing:
        raise ValueError(f"heartbeat missing fields: {', '.join(sorted(missing))}")
    if heartbeat["protocol_version"] != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol_version")
    if not isinstance(heartbeat["device_id"], str) or not heartbeat["device_id"]:
        raise ValueError("heartbeat device_id must be a non-empty string")
    if not isinstance(heartbeat["capabilities"], list):
        raise ValueError("heartbeat capabilities must be a list")
    unsupported = sorted(set(heartbeat["capabilities"]) - JOB_KINDS)
    if unsupported:
        raise ValueError(f"unsupported heartbeat capabilities: {', '.join(unsupported)}")


def companion_ask_response(request: dict[str, Any]) -> dict[str, Any]:
    validate_companion_ask(request)
    backend_url = os.environ.get("ECLIPSE_HERMES_ASK_URL", "").strip()
    if backend_url:
        return forward_companion_ask(backend_url, request)

    context_summary = companion_context_summary(request["context"])
    prompt = request["prompt"]
    return {
        "response_id": prefixed_id("ask"),
        "answer": (
            f"Hermes handoff received: “{prompt}”. "
            f"Context: {context_summary}. "
            "Set ECLIPSE_HERMES_ASK_URL on the bridge to route this to the real Hermes brain."
        ),
        "mode": "scaffold",
        "created_at": isoformat(utc_now()),
        "context_summary": context_summary,
    }


def companion_context_summary(context: dict[str, Any]) -> str:
    active_app = context.get("active_app") or {}
    window = context.get("window") or {}
    focused = context.get("focused_element") or {}
    app_name = active_app.get("name") or "your Mac"
    window_title = window.get("title") or "the active window"
    focus_label = focused.get("label") or focused.get("role") or "no focused element"
    return f"{app_name} · {window_title} · {focus_label}"


def forward_companion_ask(backend_url: str, request_body: dict[str, Any]) -> dict[str, Any]:
    payload = request_body
    if should_use_openai_chat_completions(backend_url):
        payload = openai_chat_completions_payload(request_body)

    headers = {
        "content-type": "application/json",
        "accept": "application/json",
        "user-agent": "EclipseMacBridge/0.1",
    }
    token = os.environ.get("ECLIPSE_HERMES_ASK_TOKEN", "").strip()
    if token:
        headers["authorization"] = f"Bearer {token}"
    request = Request(
        backend_url,
        data=encode_json(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urlopen(request, timeout=30) as response:
        raw = response.read()
    value = json.loads(raw.decode("utf-8")) if raw else {}
    if not isinstance(value, dict):
        raise ValueError("Hermes ask backend must return a JSON object")
    return normalize_companion_ask_backend_response(value, request_body["context"])


def should_use_openai_chat_completions(backend_url: str) -> bool:
    forced_format = os.environ.get("ECLIPSE_HERMES_ASK_FORMAT", "").strip().lower()
    if forced_format in {"openai", "chat_completions", "chat-completions"}:
        return True
    return "/v1/chat/completions" in backend_url


def openai_chat_completions_payload(request_body: dict[str, Any]) -> dict[str, Any]:
    context = request_body["context"]
    active_app = context.get("active_app") or {}
    window = context.get("window") or {}
    focused = context.get("focused_element") or {}
    visible_elements = context.get("visible_elements") or []
    selected_text = context.get("selected_text")
    focused_preview = focused.get("value_preview")
    element_labels = []
    if isinstance(visible_elements, list):
        for element in visible_elements[:12]:
            if not isinstance(element, dict):
                continue
            label = element.get("label") or element.get("role")
            if label:
                element_labels.append(str(label))

    context_lines = [
        f"Device: {request_body['device_id']}",
        f"Active app: {active_app.get('name') or 'unknown'} ({active_app.get('bundle_id') or 'unknown bundle'})",
        f"Window: {window.get('title') or 'unknown'}",
        f"Focused element: {focused.get('label') or focused.get('role') or 'unknown'}",
    ]
    if focused_preview:
        context_lines.append(f"Focused value preview: {focused_preview}")
    if selected_text:
        context_lines.append(f"Selected text: {selected_text}")
    if element_labels:
        context_lines.append("Visible elements: " + ", ".join(element_labels))

    system_prompt = (
        "You are Hermes, the brain behind Eclipse Mac. "
        "Answer from the user's current Mac context. Be concise, useful, and action-oriented. "
        "If you need the Mac tool to act, say exactly what action should happen next."
    )
    user_prompt = (
        "User prompt:\n"
        f"{request_body['prompt']}\n\n"
        "Current Mac context:\n"
        + "\n".join(context_lines)
    )
    return {
        "model": os.environ.get("ECLIPSE_HERMES_ASK_MODEL", "eclipse-mac"),
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "stream": False,
    }


def normalize_companion_ask_backend_response(value: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    if "answer" in value:
        answer = value["answer"]
        response_id = value.get("response_id")
        mode = value.get("mode") or "hermes"
        created_at = value.get("created_at")
        context_summary = value.get("context_summary")
    elif "choices" in value and isinstance(value["choices"], list) and value["choices"]:
        first_choice = value["choices"][0]
        if not isinstance(first_choice, dict):
            raise ValueError("Hermes chat completion choice must be a JSON object")
        message = first_choice.get("message") or {}
        if not isinstance(message, dict):
            raise ValueError("Hermes chat completion message must be a JSON object")
        answer = message.get("content") or first_choice.get("text")
        response_id = value.get("id")
        mode = "hermes"
        created_at = value.get("created_at")
        context_summary = None
    else:
        raise ValueError("Hermes ask backend response requires answer or choices")
    if answer is None:
        raise ValueError("Hermes ask backend response requires non-empty answer")
    return {
        "response_id": str(response_id or prefixed_id("ask")),
        "answer": str(answer),
        "mode": str(mode),
        "created_at": str(created_at or isoformat(utc_now())),
        "context_summary": context_summary or companion_context_summary(context),
    }


def validate_companion_ask(request: dict[str, Any]) -> None:
    required = {"protocol_version", "device_id", "prompt", "context", "sent_at"}
    missing = required - request.keys()
    if missing:
        raise ValueError(f"ask missing fields: {', '.join(sorted(missing))}")
    if request["protocol_version"] != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol_version")
    if not isinstance(request["device_id"], str) or not request["device_id"]:
        raise ValueError("ask device_id must be a non-empty string")
    if not isinstance(request["prompt"], str) or not request["prompt"].strip():
        raise ValueError("ask prompt must be a non-empty string")
    if not isinstance(request["context"], dict):
        raise ValueError("ask context must be a JSON object")


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
        if parsed.path == "/jobs":
            self.respond({"jobs": self.server.state.all_jobs()})
            return
        if parsed.path == "/stats":
            self.respond(self.server.state.stats())
            return
        if parsed.path == "/devices":
            self.respond({"devices": self.server.state.all_devices()})
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
            if parsed.path == "/ask":
                self.respond(companion_ask_response(body), status=200)
                return
            if parsed.path == "/heartbeats":
                heartbeat = self.server.state.save_heartbeat(body)
                self.respond({"heartbeat": heartbeat}, status=201)
                return
            if parsed.path.startswith("/jobs/") and parsed.path.endswith("/cancel"):
                job_id = parsed.path.split("/")[-2]
                result, cancelled = self.server.state.cancel_job(
                    job_id,
                    message=body.get("message", "Job cancelled before delivery"),
                )
                if result is None:
                    self.error(404, "queued job not found")
                    return
                self.respond({"cancelled": cancelled, "result": result})
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
        state: BridgeState | SQLiteBridgeState | None = None,
        token: str | None = None,
    ):
        super().__init__(address, BridgeHandler)
        self.state = state or BridgeState()
        self.token = token


def make_server(
    host: str = "127.0.0.1",
    port: int = 8765,
    token: str | None = None,
    state: BridgeState | SQLiteBridgeState | None = None,
) -> BridgeHTTPServer:
    return BridgeHTTPServer((host, port), state=state, token=token)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the local Eclipse Mac mock bridge.")
    parser.add_argument("--host", default=os.environ.get("ECLIPSE_BRIDGE_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("ECLIPSE_BRIDGE_PORT", "8765")))
    parser.add_argument(
        "--token",
        default=os.environ.get("ECLIPSE_BRIDGE_TOKEN"),
        help="Optional bearer token. Also read from ECLIPSE_BRIDGE_TOKEN.",
    )
    parser.add_argument(
        "--db",
        default=os.environ.get("ECLIPSE_BRIDGE_DB"),
        help="Optional SQLite database path. Also read from ECLIPSE_BRIDGE_DB.",
    )
    args = parser.parse_args()

    state = SQLiteBridgeState(args.db) if args.db else None
    server = make_server(args.host, args.port, token=args.token, state=state)
    auth = " with bearer auth" if args.token else ""
    storage = f" using sqlite {args.db}" if args.db else " using memory"
    print(f"mock bridge listening on http://{args.host}:{args.port}{auth}{storage}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
