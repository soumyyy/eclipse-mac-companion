import threading
import unittest
from pathlib import Path

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
