import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mock_bridge import SQLiteBridgeState, make_server  # noqa: E402


class MockBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server(port=0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        host, port = cls.server.server_address
        cls.base_url = f"http://{host}:{port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def test_creates_and_delivers_job(self):
        job = self.post("/jobs", {
            "device_id": "mac_test",
            "kind": "context.get_active_window",
            "risk": "read",
            "input": {},
        }, expected_status=201)

        self.assertEqual(job["protocol_version"], "0.1")
        self.assertEqual(job["kind"], "context.get_active_window")

        delivered = self.get("/jobs/next", {"device_id": "mac_test"})
        self.assertEqual(delivered["job_id"], job["job_id"])

    def test_rejects_invalid_set_text_job(self):
        with self.assertRaises(HTTPError) as caught:
            self.post("/jobs", {
                "device_id": "mac_test",
                "kind": "ui.set_text",
                "risk": "read",
                "input": {},
            })

        self.assertEqual(caught.exception.code, 400)
        caught.exception.read()
        caught.exception.close()

    def test_accepts_new_mvp_job_kinds(self):
        cases = [
            ("context.capture_window", "read", {}),
            ("notification.show", "reversible", {"title": "Hello", "body": "From test"}),
            ("ui.press_key", "reversible", {"key": "escape", "modifiers": []}),
            ("ui.click_element", "consequential", {"element_role": "AXButton", "element_label": "Continue"}),
        ]

        for kind, risk, input_body in cases:
            with self.subTest(kind=kind):
                job = self.post("/jobs", {
                    "device_id": "mac_test_new_kinds",
                    "kind": kind,
                    "risk": risk,
                    "input": input_body,
                }, expected_status=201)
                self.assertEqual(job["kind"], kind)

    def test_rejects_unsupported_key_press(self):
        with self.assertRaises(HTTPError) as caught:
            self.post("/jobs", {
                "device_id": "mac_test",
                "kind": "ui.press_key",
                "risk": "reversible",
                "input": {"key": "command_q", "modifiers": []},
            })

        self.assertEqual(caught.exception.code, 400)
        caught.exception.read()
        caught.exception.close()

    def test_accepts_result_and_replays_duplicate_by_idempotency_key(self):
        result = {
            "job_id": "job_test",
            "protocol_version": "0.1",
            "device_id": "mac_test",
            "status": "succeeded",
            "output": {
                "action_result": {
                    "action_id": "act_test",
                    "snapshot_id": "ctx_test",
                    "completed_at": "2026-07-15T12:00:05Z",
                    "characters_written": 5,
                }
            },
            "completed_at": "2026-07-15T12:00:05Z",
            "idempotency_key": "idem_test",
        }

        first = self.post("/results", result)
        second = self.post("/results", result)
        fetched = self.get("/results/job_test")

        self.assertFalse(first["duplicate"])
        self.assertTrue(second["duplicate"])
        self.assertEqual(fetched["idempotency_key"], "idem_test")

    def test_cancels_queued_job_and_stores_rejected_result(self):
        job = self.post("/jobs", {
            "device_id": "mac_cancel_test",
            "kind": "context.get_active_window",
            "risk": "read",
            "input": {},
        }, expected_status=201)

        cancelled = self.post(f"/jobs/{job['job_id']}/cancel", {"message": "No longer needed"})
        result = self.get(f"/results/{job['job_id']}")
        jobs = self.get("/jobs")

        self.assertTrue(cancelled["cancelled"])
        self.assertEqual(cancelled["result"]["status"], "rejected")
        self.assertEqual(cancelled["result"]["error"]["code"], "cancelled_before_delivery")
        self.assertEqual(result["error"]["message"], "No longer needed")
        self.assertFalse(any(item["job_id"] == job["job_id"] for item in jobs["jobs"]))

    def test_accepts_heartbeat_and_lists_device_presence(self):
        heartbeat = {
            "protocol_version": "0.1",
            "device_id": "mac_presence_test",
            "sent_at": "2026-07-15T12:00:00Z",
            "capabilities": [
                "context.get_active_window",
                "context.capture_window",
                "notification.show",
                "ui.set_text",
                "ui.press_key",
                "ui.click_element",
            ],
            "status": "polling",
            "outbox_count": 2,
        }

        posted = self.post("/heartbeats", heartbeat, expected_status=201)
        devices = self.get("/devices")

        self.assertEqual(posted["heartbeat"]["device_id"], "mac_presence_test")
        listed = [device for device in devices["devices"] if device["device_id"] == "mac_presence_test"]
        self.assertEqual(len(listed), 1)
        self.assertEqual(listed[0]["status"], "polling")
        self.assertEqual(listed[0]["outbox_count"], 2)

    def test_accepts_companion_ask_and_returns_contextual_scaffold(self):
        response = self.post("/ask", {
            "protocol_version": "0.1",
            "device_id": "mac_ask_test",
            "prompt": "What am I looking at?",
            "sent_at": "2026-07-15T12:00:00Z",
            "context": {
                "snapshot_id": "ctx_test",
                "captured_at": "2026-07-15T12:00:00Z",
                "active_app": {"bundle_id": "com.apple.Notes", "name": "Notes"},
                "window": {"id": 123, "title": "Meeting notes"},
                "focused_element": {"role": "AXTextArea", "label": "Body", "value_preview": "Hello"},
                "selected_text": None,
                "visible_elements": [],
                "screenshot_ref": None,
                "redactions": [],
            },
        })

        self.assertEqual(response["mode"], "scaffold")
        self.assertIn("What am I looking at?", response["answer"])
        self.assertEqual(response["context_summary"], "Notes · Meeting notes · Body")

    def test_replays_outbox_batch(self):
        body = {
            "results": [
                {
                    "job_id": "job_outbox",
                    "protocol_version": "0.1",
                    "device_id": "mac_test",
                    "status": "pending_approval",
                    "completed_at": "2026-07-15T12:00:01Z",
                    "idempotency_key": "idem_outbox",
                }
            ]
        }

        first = self.post("/outbox/replay", body)
        second = self.post("/outbox/replay", body)

        self.assertEqual(first["accepted"], 1)
        self.assertEqual(first["duplicates"], 0)
        self.assertEqual(second["accepted"], 0)
        self.assertEqual(second["duplicates"], 1)

    def test_health_reports_auth_mode(self):
        health = self.get("/health")

        self.assertTrue(health["ok"])
        self.assertFalse(health["auth_required"])

    def test_lists_jobs_and_stats_without_consuming_queue(self):
        job = self.post("/jobs", {
            "device_id": "mac_list_test",
            "kind": "context.get_active_window",
            "risk": "read",
            "input": {},
        }, expected_status=201)

        jobs = self.get("/jobs")
        stats = self.get("/stats")
        delivered = self.get("/jobs/next", {"device_id": "mac_list_test"})

        self.assertTrue(any(item["job_id"] == job["job_id"] for item in jobs["jobs"]))
        self.assertGreaterEqual(stats["queued_jobs"], 1)
        self.assertGreaterEqual(stats["results"], 0)
        self.assertEqual(delivered["job_id"], job["job_id"])

    def test_sqlite_state_persists_queued_jobs_and_results(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "bridge.sqlite3")
            first = SQLiteBridgeState(path)
            job = first.create_job({
                "device_id": "mac_test",
                "kind": "context.get_active_window",
                "risk": "read",
                "input": {},
            })
            result = {
                "job_id": "job_persisted",
                "protocol_version": "0.1",
                "device_id": "mac_test",
                "status": "succeeded",
                "completed_at": "2026-07-15T12:00:05Z",
                "idempotency_key": "idem_persisted",
            }
            first.save_result(result)

            second = SQLiteBridgeState(path)

            self.assertEqual(second.stats(), {"queued_jobs": 1, "results": 1})
            self.assertEqual(second.all_jobs()[0]["job_id"], job["job_id"])
            self.assertEqual(second.next_job("mac_test")["job_id"], job["job_id"])
            self.assertEqual(second.result("job_persisted")["idempotency_key"], "idem_persisted")
            duplicate, is_duplicate = second.save_result(result)
            self.assertTrue(is_duplicate)
            self.assertEqual(duplicate["job_id"], "job_persisted")

    def test_sqlite_state_cancels_queued_job_and_persists_result(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "bridge.sqlite3")
            first = SQLiteBridgeState(path)
            job = first.create_job({
                "device_id": "mac_test",
                "kind": "context.get_active_window",
                "risk": "read",
                "input": {},
            })

            result, cancelled = first.cancel_job(job["job_id"], message="Timed out")
            second = SQLiteBridgeState(path)

            self.assertTrue(cancelled)
            self.assertEqual(result["status"], "rejected")
            self.assertEqual(second.stats(), {"queued_jobs": 0, "results": 1})
            self.assertEqual(second.result(job["job_id"])["error"]["message"], "Timed out")

    def test_sqlite_state_persists_latest_heartbeat(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "bridge.sqlite3")
            first = SQLiteBridgeState(path)
            first.save_heartbeat({
                "protocol_version": "0.1",
                "device_id": "mac_sqlite_presence",
                "sent_at": "2026-07-15T12:00:00Z",
                "capabilities": ["context.get_active_window"],
                "status": "online",
            })
            first.save_heartbeat({
                "protocol_version": "0.1",
                "device_id": "mac_sqlite_presence",
                "sent_at": "2026-07-15T12:00:05Z",
                "capabilities": ["context.get_active_window", "ui.set_text"],
                "status": "polling",
            })

            second = SQLiteBridgeState(path)
            devices = second.all_devices()

            self.assertEqual(len(devices), 1)
            self.assertEqual(devices[0]["status"], "polling")
            self.assertEqual(devices[0]["capabilities"], ["context.get_active_window", "ui.set_text"])

    def test_token_protected_bridge_rejects_and_accepts_authorized_requests(self):
        server = make_server(port=0, token="secret_test_token")
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        host, port = server.server_address
        base_url = f"http://{host}:{port}"

        try:
            with urlopen(base_url + "/health", timeout=5) as response:
                health = json.loads(response.read().decode("utf-8"))
                self.assertTrue(health["auth_required"])

            with self.assertRaises(HTTPError) as caught:
                urlopen(base_url + "/jobs/next?device_id=mac_test", timeout=5)
            self.assertEqual(caught.exception.code, 401)
            caught.exception.read()
            caught.exception.close()

            request = Request(
                base_url + "/jobs",
                data=json.dumps({
                    "device_id": "mac_test",
                    "kind": "context.get_active_window",
                    "risk": "read",
                    "input": {},
                }).encode("utf-8"),
                headers={
                    "authorization": "Bearer secret_test_token",
                    "content-type": "application/json",
                },
                method="POST",
            )
            with urlopen(request, timeout=5) as response:
                self.assertEqual(response.status, 201)
                body = json.loads(response.read().decode("utf-8"))
                self.assertEqual(body["device_id"], "mac_test")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def get(self, path, query=None):
        url = self.base_url + path
        if query:
            url += "?" + urlencode(query)
        with urlopen(url, timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))

    def post(self, path, body, expected_status=200):
        request = Request(
            self.base_url + path,
            data=json.dumps(body).encode("utf-8"),
            headers={"content-type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=5) as response:
            self.assertEqual(response.status, expected_status)
            return json.loads(response.read().decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
