import json
import subprocess
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mock_bridge import make_server  # noqa: E402


class BridgeCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server(port=0, token="cli_test_token")
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        host, port = cls.server.server_address
        cls.base_url = f"http://{host}:{port}"
        cls.cli = Path(__file__).resolve().parents[1] / "bridge_cli.py"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def test_health_does_not_require_token(self):
        response = self.run_cli("health")

        self.assertTrue(response["ok"])
        self.assertTrue(response["auth_required"])

    def test_create_context_list_jobs_and_stats(self):
        job = self.run_cli(
            "create-context",
            "--device-id",
            "mac_cli_test",
            "--idempotency-key",
            "idem_cli_context",
        )
        jobs = self.run_cli("jobs")
        stats = self.run_cli("stats")

        self.assertEqual(job["kind"], "context.get_active_window")
        self.assertTrue(any(item["job_id"] == job["job_id"] for item in jobs["jobs"]))
        self.assertGreaterEqual(stats["queued_jobs"], 1)

    def test_create_set_text_job(self):
        job = self.run_cli(
            "create-set-text",
            "--device-id",
            "mac_cli_text",
            "Hello from CLI",
        )

        self.assertEqual(job["kind"], "ui.set_text")
        self.assertEqual(job["risk"], "reversible")
        self.assertEqual(job["input"]["text"], "Hello from CLI")

    def test_create_new_mvp_jobs(self):
        capture = self.run_cli("create-capture-window", "--device-id", "mac_cli_capture")
        notification = self.run_cli(
            "create-notification",
            "--device-id",
            "mac_cli_notification",
            "--body",
            "Body",
            "Title",
        )
        key = self.run_cli("create-press-key", "--device-id", "mac_cli_key", "escape")
        click = self.run_cli(
            "create-click-element",
            "--device-id",
            "mac_cli_click",
            "--element-label",
            "Continue",
            "AXButton",
        )

        self.assertEqual(capture["kind"], "context.capture_window")
        self.assertEqual(notification["input"]["title"], "Title")
        self.assertEqual(key["input"]["key"], "escape")
        self.assertEqual(click["input"]["element_role"], "AXButton")

    def test_cancel_queued_job(self):
        job = self.run_cli(
            "create-context",
            "--device-id",
            "mac_cli_cancel",
            "--idempotency-key",
            "idem_cli_cancel",
        )

        cancelled = self.run_cli("cancel", job["job_id"], "--message", "CLI cancelled")

        self.assertTrue(cancelled["cancelled"])
        self.assertEqual(cancelled["result"]["status"], "rejected")
        self.assertEqual(cancelled["result"]["error"]["message"], "CLI cancelled")

    def run_cli(self, *args):
        completed = subprocess.run(
            [
                sys.executable,
                str(self.cli),
                "--url",
                self.base_url,
                "--token",
                "cli_test_token",
                *args,
            ],
            check=True,
            text=True,
            capture_output=True,
        )
        return json.loads(completed.stdout)


if __name__ == "__main__":
    unittest.main()
