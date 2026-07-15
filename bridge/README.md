# Local Mock Bridge

This is a development-only HTTP bridge for testing the Mac worker contract before the real VPS bridge exists.

Run it with:

```bash
python3 bridge/mock_bridge.py --port 8765
```

Run it with bearer-token auth:

```bash
ECLIPSE_BRIDGE_TOKEN='replace-with-a-long-random-token' python3 bridge/mock_bridge.py --host 0.0.0.0 --port 8765
```

Run it with durable SQLite storage:

```bash
ECLIPSE_BRIDGE_DB='./bridge.sqlite3' python3 bridge/mock_bridge.py --port 8765
```

When a token is configured, all job/result endpoints require:

```text
Authorization: Bearer replace-with-a-long-random-token
```

`GET /health` stays public and reports whether auth is required. For a VPS, put the bridge behind HTTPS before entering a token in the Mac app.

Useful endpoints:

- `GET /health`
- `POST /jobs`
- `GET /jobs/next?device_id=mac_soumya_local`
- `POST /results`
- `POST /outbox/replay`
- `GET /results`
- `GET /results/{job_id}`

The server stores jobs and results in memory. It validates the same MVP constraints as the Swift local bridge: protocol `0.1`, supported job kinds, risk matching, and required `input.text` for `ui.set_text`.

Minimal VPS profile:

- Bind the Python bridge to `127.0.0.1:8765` behind a reverse proxy, or `0.0.0.0:8765` only behind a firewall/VPN.
- Set `ECLIPSE_BRIDGE_TOKEN` to a long random value.
- Terminate TLS at the reverse proxy and use an `https://` bridge URL in the Mac app.
- Enter the same bearer token in the overlay token field.
- Set `ECLIPSE_BRIDGE_DB` so jobs/results survive service restarts.
- Keep this bridge for development only; the SQLite-backed mode is durable enough for MVP testing but not a full production queue.
