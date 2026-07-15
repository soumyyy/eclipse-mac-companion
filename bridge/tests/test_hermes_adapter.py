import json
import threading
import unittest
from pathlib import Path
from subprocess import run

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from hermes_adapter import EclipseMacHermesAdapter  # noqa: E402
from mock_bridge import make_server  # noqa: E402


class HermesAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = make_server(port=0, token="adapter_test_token")
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        host, port = cls.server.server_address
        cls.base_url = f"http://{host}:{port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def test_adapter_enqueues_typed_job(self):
        adapter = EclipseMacHermesAdapter(
            bridge_url=self.base_url,
            token="adapter_test_token",
            device_id="mac_adapter_test",
        )

        response = adapter.show_notification("Hello", "Body", wait=False)

        self.assertEqual(response["job"]["kind"], "notification.show")
        self.assertEqual(response["job"]["device_id"], "mac_adapter_test")
        self.assertIsNone(response["result"])
        self.assertFalse(response["timed_out"])

    def test_adapter_lists_and_invokes_tool_contract(self):
        adapter = EclipseMacHermesAdapter(
            bridge_url=self.base_url,
            token="adapter_test_token",
            device_id="mac_adapter_tools",
        )

        tool_names = [tool["name"] for tool in adapter.list_tools()]
        response = adapter.invoke_tool("mac.show_notification", {"title": "Tool hello", "body": "Body"}, wait=False)

        self.assertIn("mac.get_active_window", tool_names)
        self.assertIn("mac.press_key", tool_names)
        self.assertEqual(response["job"]["kind"], "notification.show")
        self.assertEqual(response["job"]["input"]["title"], "Tool hello")

    def test_adapter_posts_heartbeat_and_lists_devices(self):
        adapter = EclipseMacHermesAdapter(
            bridge_url=self.base_url,
            token="adapter_test_token",
            device_id="mac_adapter_presence",
        )

        heartbeat = adapter.post_heartbeat(status="online")
        devices = adapter.list_devices()

        self.assertEqual(heartbeat["heartbeat"]["device_id"], "mac_adapter_presence")
        self.assertTrue(any(device["device_id"] == "mac_adapter_presence" for device in devices["devices"]))

    def test_tool_host_invokes_tool_as_json_command(self):
        script = Path(__file__).resolve().parents[1] / "hermes_tool_host.py"

        completed = run(
            [
                sys.executable,
                str(script),
                "--url",
                self.base_url,
                "--token",
                "adapter_test_token",
                "--device-id",
                "mac_tool_host",
                "call",
                "mac.press_key",
                "--arguments",
                '{"key":"escape"}',
                "--no-wait",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        body = json.loads(completed.stdout)
        self.assertEqual(body["job"]["kind"], "ui.press_key")
        self.assertEqual(body["job"]["input"]["key"], "escape")

    def test_tool_host_accepts_timeout_after_call_subcommand(self):
        script = Path(__file__).resolve().parents[1] / "hermes_tool_host.py"

        completed = run(
            [
                sys.executable,
                str(script),
                "--url",
                self.base_url,
                "--token",
                "adapter_test_token",
                "--device-id",
                "mac_tool_host_timeout",
                "call",
                "mac.get_active_window",
                "--arguments",
                "{}",
                "--wait",
                "--timeout-seconds",
                "0.01",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        body = json.loads(completed.stdout)
        self.assertTrue(body["timed_out"])
        self.assertTrue(body["cancellation"]["cancelled"])

    def test_adapter_cancels_queued_job_on_timeout(self):
        adapter = EclipseMacHermesAdapter(
            bridge_url=self.base_url,
            token="adapter_test_token",
            device_id="mac_adapter_timeout",
            timeout_seconds=0.01,
        )

        response = adapter.get_active_window(wait=True)

        self.assertTrue(response["timed_out"])
        self.assertIsNone(response["result"])
        self.assertTrue(response["cancellation"]["cancelled"])
        self.assertEqual(response["cancellation"]["result"]["status"], "rejected")

    def test_adapter_can_leave_timed_out_job_queued(self):
        adapter = EclipseMacHermesAdapter(
            bridge_url=self.base_url,
            token="adapter_test_token",
            device_id="mac_adapter_no_cancel",
            timeout_seconds=0.01,
        )

        response = adapter.capture_window(wait=True, cancel_on_timeout=False)

        self.assertTrue(response["timed_out"])
        self.assertIsNone(response["cancellation"])


if __name__ == "__main__":
    unittest.main()
