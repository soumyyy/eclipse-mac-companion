#!/usr/bin/env python3
"""Thin Hermes-facing adapter for the Eclipse Mac development bridge.

This module intentionally stays small: it translates higher-level Hermes tool
calls into typed bridge jobs and optionally waits for the Mac worker's result.
The Mac remains the policy and execution authority.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class EclipseMacHermesAdapter:
    TOOL_SCHEMAS: dict[str, dict[str, Any]] = {
        "mac.get_active_window": {
            "description": "Return the active app/window context from the Mac worker.",
            "input_schema": {"type": "object", "additionalProperties": False, "properties": {}},
            "wait_default": True,
        },
        "mac.capture_window": {
            "description": "Capture metadata for the active Mac window.",
            "input_schema": {"type": "object", "additionalProperties": False, "properties": {}},
            "wait_default": True,
        },
        "mac.show_notification": {
            "description": "Ask the Mac to show a local notification.",
            "input_schema": {
                "type": "object",
                "additionalProperties": False,
                "required": ["title"],
                "properties": {
                    "title": {"type": "string", "minLength": 1},
                    "body": {"type": "string"},
                },
            },
            "wait_default": True,
        },
        "mac.type_text": {
            "description": "Request Mac-side approval to type text into the current focused field.",
            "input_schema": {
                "type": "object",
                "additionalProperties": False,
                "required": ["text"],
                "properties": {"text": {"type": "string", "minLength": 1}},
            },
            "wait_default": True,
        },
        "mac.press_key": {
            "description": "Request Mac-side approval to press a small allowed key.",
            "input_schema": {
                "type": "object",
                "additionalProperties": False,
                "required": ["key"],
                "properties": {
                    "key": {"type": "string", "minLength": 1},
                    "modifiers": {"type": "array", "items": {"type": "string"}},
                },
            },
            "wait_default": True,
        },
        "mac.click_element": {
            "description": "Request Mac-side approval to AXPress an exact role/label matched element.",
            "input_schema": {
                "type": "object",
                "additionalProperties": False,
                "required": ["element_role"],
                "properties": {
                    "element_role": {"type": "string", "minLength": 1},
                    "element_label": {"type": "string"},
                },
            },
            "wait_default": True,
        },
    }

    def __init__(
        self,
        bridge_url: str | None = None,
        token: str | None = None,
        device_id: str | None = None,
        timeout_seconds: float = 30,
    ):
        self.bridge_url = (bridge_url or os.environ.get("ECLIPSE_BRIDGE_URL") or "http://127.0.0.1:8765").rstrip("/")
        self.token = token if token is not None else os.environ.get("ECLIPSE_BRIDGE_TOKEN", "")
        self.device_id = device_id or os.environ.get("ECLIPSE_MAC_DEVICE_ID", "mac_soumya_local")
        self.timeout_seconds = timeout_seconds

    @classmethod
    def list_tools(cls) -> list[dict[str, Any]]:
        return [
            {
                "name": name,
                "description": spec["description"],
                "input_schema": spec["input_schema"],
                "wait_default": spec["wait_default"],
            }
            for name, spec in sorted(cls.TOOL_SCHEMAS.items())
        ]

    def invoke_tool(
        self,
        name: str,
        arguments: dict[str, Any] | None = None,
        *,
        wait: bool | None = None,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        arguments = arguments or {}
        if name not in self.TOOL_SCHEMAS:
            raise ValueError(f"Unsupported Hermes Mac tool: {name}")
        if not isinstance(arguments, dict):
            raise ValueError("Tool arguments must be a JSON object")
        effective_wait = self.TOOL_SCHEMAS[name]["wait_default"] if wait is None else wait

        if name == "mac.get_active_window":
            return self.get_active_window(
                wait=effective_wait,
                timeout_seconds=timeout_seconds,
                cancel_on_timeout=cancel_on_timeout,
            )
        if name == "mac.capture_window":
            return self.capture_window(
                wait=effective_wait,
                timeout_seconds=timeout_seconds,
                cancel_on_timeout=cancel_on_timeout,
            )
        if name == "mac.show_notification":
            return self.show_notification(
                require_string(arguments, "title"),
                str(arguments.get("body", "")),
                wait=effective_wait,
                timeout_seconds=timeout_seconds,
                cancel_on_timeout=cancel_on_timeout,
            )
        if name == "mac.type_text":
            return self.type_text_with_approval(
                require_string(arguments, "text"),
                wait=effective_wait,
                timeout_seconds=timeout_seconds,
                cancel_on_timeout=cancel_on_timeout,
            )
        if name == "mac.press_key":
            modifiers = arguments.get("modifiers", [])
            if modifiers is None:
                modifiers = []
            if not isinstance(modifiers, list) or not all(isinstance(item, str) for item in modifiers):
                raise ValueError("modifiers must be a list of strings")
            return self.press_key_with_approval(
                require_string(arguments, "key"),
                modifiers=modifiers,
                wait=effective_wait,
                timeout_seconds=timeout_seconds,
                cancel_on_timeout=cancel_on_timeout,
            )
        if name == "mac.click_element":
            label = arguments.get("element_label")
            if label is not None and not isinstance(label, str):
                raise ValueError("element_label must be a string when provided")
            return self.click_element_with_approval(
                require_string(arguments, "element_role"),
                element_label=label,
                wait=effective_wait,
                timeout_seconds=timeout_seconds,
                cancel_on_timeout=cancel_on_timeout,
            )
        raise ValueError(f"Unsupported Hermes Mac tool: {name}")

    def get_active_window(
        self,
        *,
        wait: bool = True,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        return self.enqueue_or_wait(
            "context.get_active_window",
            "read",
            {},
            wait=wait,
            timeout_seconds=timeout_seconds,
            cancel_on_timeout=cancel_on_timeout,
        )

    def capture_window(
        self,
        *,
        wait: bool = True,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        return self.enqueue_or_wait(
            "context.capture_window",
            "read",
            {},
            wait=wait,
            timeout_seconds=timeout_seconds,
            cancel_on_timeout=cancel_on_timeout,
        )

    def show_notification(
        self,
        title: str,
        body: str = "",
        *,
        wait: bool = False,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        return self.enqueue_or_wait(
            "notification.show",
            "reversible",
            {"title": title, "body": body},
            wait=wait,
            timeout_seconds=timeout_seconds,
            cancel_on_timeout=cancel_on_timeout,
        )

    def type_text_with_approval(
        self,
        text: str,
        *,
        wait: bool = False,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        return self.enqueue_or_wait(
            "ui.set_text",
            "reversible",
            {"text": text},
            wait=wait,
            timeout_seconds=timeout_seconds,
            cancel_on_timeout=cancel_on_timeout,
        )

    def press_key_with_approval(
        self,
        key: str,
        modifiers: list[str] | None = None,
        *,
        wait: bool = False,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        return self.enqueue_or_wait(
            "ui.press_key",
            "reversible",
            {"key": key, "modifiers": modifiers or []},
            wait=wait,
            timeout_seconds=timeout_seconds,
            cancel_on_timeout=cancel_on_timeout,
        )

    def click_element_with_approval(
        self,
        element_role: str,
        element_label: str | None = None,
        *,
        wait: bool = False,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        input_body: dict[str, Any] = {"element_role": element_role}
        if element_label:
            input_body["element_label"] = element_label
        return self.enqueue_or_wait(
            "ui.click_element",
            "consequential",
            input_body,
            wait=wait,
            timeout_seconds=timeout_seconds,
            cancel_on_timeout=cancel_on_timeout,
        )

    def enqueue_or_wait(
        self,
        kind: str,
        risk: str,
        input_body: dict[str, Any],
        *,
        wait: bool,
        timeout_seconds: float | None = None,
        cancel_on_timeout: bool = True,
    ) -> dict[str, Any]:
        job = self.create_job(kind=kind, risk=risk, input_body=input_body)
        if not wait:
            return {"job": job, "result": None, "timed_out": False, "cancellation": None}
        try:
            return {
                "job": job,
                "result": self.wait_for_result(job["job_id"], timeout_seconds=timeout_seconds),
                "timed_out": False,
                "cancellation": None,
            }
        except TimeoutError:
            cancellation = self.cancel_job(job["job_id"]) if cancel_on_timeout else None
            return {
                "job": job,
                "result": None,
                "timed_out": True,
                "cancellation": cancellation,
            }

    def create_job(self, *, kind: str, risk: str, input_body: dict[str, Any]) -> dict[str, Any]:
        return self.request_json(
            "POST",
            "/jobs",
            {
                "device_id": self.device_id,
                "kind": kind,
                "risk": risk,
                "input": input_body,
                "ttl_seconds": int(self.timeout_seconds),
            },
        )

    def cancel_job(self, job_id: str, message: str = "Timed out waiting for Mac result") -> dict[str, Any]:
        return self.request_json("POST", f"/jobs/{job_id}/cancel", {"message": message})

    def post_heartbeat(self, status: str = "online", app_version: str = "hermes-adapter") -> dict[str, Any]:
        return self.request_json(
            "POST",
            "/heartbeats",
            {
                "protocol_version": "0.1",
                "device_id": self.device_id,
                "sent_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "capabilities": [
                    "context.get_active_window",
                    "context.capture_window",
                    "notification.show",
                    "ui.set_text",
                    "ui.press_key",
                    "ui.click_element",
                ],
                "status": status,
                "app_version": app_version,
            },
        )

    def list_devices(self) -> dict[str, Any]:
        return self.request_json("GET", "/devices")

    def wait_for_result(self, job_id: str, timeout_seconds: float | None = None) -> dict[str, Any]:
        deadline = time.monotonic() + (timeout_seconds if timeout_seconds is not None else self.timeout_seconds)
        while time.monotonic() < deadline:
            try:
                return self.request_json("GET", f"/results/{job_id}")
            except HTTPError as error:
                if error.code != 404:
                    raise
                error.read()
                error.close()
            time.sleep(0.5)
        raise TimeoutError(f"Timed out waiting for bridge result {job_id}")

    def request_json(self, method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        headers = {
            "accept": "application/json",
            "user-agent": "EclipseMacHermesAdapter/0.1",
        }
        data = None
        if body is not None:
            headers["content-type"] = "application/json"
            data = json.dumps(body).encode("utf-8")
        if self.token:
            headers["authorization"] = f"Bearer {self.token}"

        request = Request(self.bridge_url + path, data=data, headers=headers, method=method)
        with urlopen(request, timeout=10) as response:
            raw = response.read()
        return json.loads(raw.decode("utf-8")) if raw else {}


def require_string(arguments: dict[str, Any], key: str) -> str:
    value = arguments.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} must be a non-empty string")
    return value
