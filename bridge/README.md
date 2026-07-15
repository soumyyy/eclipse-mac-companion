# Local Mock Bridge

This is a development-only HTTP bridge for testing the Mac worker contract before the real VPS bridge exists.

Run it with:

```bash
python3 bridge/mock_bridge.py --port 8765
```

Useful endpoints:

- `GET /health`
- `POST /jobs`
- `GET /jobs/next?device_id=mac_soumya_local`
- `POST /results`
- `POST /outbox/replay`
- `GET /results`
- `GET /results/{job_id}`

The server stores jobs and results in memory. It validates the same MVP constraints as the Swift local bridge: protocol `0.1`, supported job kinds, risk matching, and required `input.text` for `ui.set_text`.
