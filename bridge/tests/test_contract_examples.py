import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ContractExampleTests(unittest.TestCase):
    def test_required_schema_files_exist(self):
        for name in [
            "job",
            "result",
            "event",
            "approval",
            "heartbeat",
            "error",
        ]:
            path = ROOT / "schemas" / f"{name}.schema.json"
            self.assertTrue(path.exists(), path)
            schema = json.loads(path.read_text())
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")

    def test_job_examples_match_mvp_wire_contract(self):
        for path in (ROOT / "examples" / "jobs").glob("*.json"):
            job = json.loads(path.read_text())
            self.assertEqual(job["protocol_version"], "0.1")
            self.assertIn(job["kind"], {"context.get_active_window", "ui.set_text"})
            self.assertIn(job["risk"], {"read", "reversible", "consequential"})
            self.assertTrue(job["job_id"].startswith("job_"))
            self.assertTrue(job["idempotency_key"].startswith("idem_"))
            if job["kind"] == "ui.set_text":
                self.assertEqual(job["risk"], "reversible")
                self.assertTrue(job["input"]["text"])
            if job["kind"] == "context.get_active_window":
                self.assertEqual(job["risk"], "read")
                self.assertEqual(job["input"], {})

    def test_result_examples_match_mvp_wire_contract(self):
        for path in (ROOT / "examples" / "results").glob("*.json"):
            result = json.loads(path.read_text())
            self.assertEqual(result["protocol_version"], "0.1")
            self.assertIn(result["status"], {
                "succeeded",
                "failed",
                "rejected",
                "expired",
                "pending_approval",
            })
            self.assertTrue(result["job_id"].startswith("job_"))
            self.assertTrue(result["idempotency_key"].startswith("idem_"))


if __name__ == "__main__":
    unittest.main()
