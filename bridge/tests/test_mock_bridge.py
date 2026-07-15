import json
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mock_bridge import make_server  # noqa: E402


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
