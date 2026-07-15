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

    def get_active_window(self, *, wait: bool = True) -> dict[str, Any]:
        return self.enqueue_or_wait("context.get_active_window", "read", {}, wait=wait)

    def capture_window(self, *, wait: bool = True) -> dict[str, Any]:
        return self.enqueue_or_wait("context.capture_window", "read", {}, wait=wait)

    def show_notification(self, title: str, body: str = "", *, wait: bool = False) -> dict[str, Any]:
        return self.enqueue_or_wait("notification.show", "reversible", {"title": title, "body": body}, wait=wait)

    def type_text_with_approval(self, text: str, *, wait: bool = False) -> dict[str, Any]:
        return self.enqueue_or_wait("ui.set_text", "reversible", {"text": text}, wait=wait)

    def press_key_with_approval(
        self,
        key: str,
        modifiers: list[str] | None = None,
        *,
        wait: bool = False,
    ) -> dict[str, Any]:
        return self.enqueue_or_wait(
            "ui.press_key",
            "reversible",
            {"key": key, "modifiers": modifiers or []},
            wait=wait,
        )

    def click_element_with_approval(
        self,
        element_role: str,
        element_label: str | None = None,
        *,
        wait: bool = False,
    ) -> dict[str, Any]:
        input_body: dict[str, Any] = {"element_role": element_role}
        if element_label:
            input_body["element_label"] = element_label
        return self.enqueue_or_wait("ui.click_element", "consequential", input_body, wait=wait)

    def enqueue_or_wait(
        self,
        kind: str,
        risk: str,
        input_body: dict[str, Any],
        *,
        wait: bool,
    ) -> dict[str, Any]:
        job = self.create_job(kind=kind, risk=risk, input_body=input_body)
        if not wait:
            return {"job": job, "result": None}
        return {"job": job, "result": self.wait_for_result(job["job_id"])}

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

    def wait_for_result(self, job_id: str) -> dict[str, Any]:
        deadline = time.monotonic() + self.timeout_seconds
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
