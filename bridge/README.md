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
- `GET /jobs`
- `GET /jobs/next?device_id=mac_soumya_local`
- `POST /results`
- `POST /outbox/replay`
- `GET /results`
- `GET /results/{job_id}`
- `GET /stats`

Without `ECLIPSE_BRIDGE_DB`, the server stores jobs and results in memory. With `ECLIPSE_BRIDGE_DB`, queued jobs and results are stored in SQLite. It validates the same MVP constraints as the Swift local bridge: protocol `0.1`, supported job kinds, risk matching, and required `input.text` for `ui.set_text`.

The Mac app can also create bridge jobs from **Settings → Bridge**. The command composer supports `context.get_active_window` and `ui.set_text`; text jobs still require Mac-side approval before typing. The same Settings panel can refresh bridge activity to show queued jobs and recent results.

Operator CLI:

```bash
export ECLIPSE_BRIDGE_URL='https://bridge.eclipsn.com'
export ECLIPSE_BRIDGE_TOKEN='replace-with-the-vps-token'

python3 bridge/bridge_cli.py health
python3 bridge/bridge_cli.py stats
python3 bridge/bridge_cli.py jobs
python3 bridge/bridge_cli.py results
python3 bridge/bridge_cli.py create-context
python3 bridge/bridge_cli.py create-set-text 'Hello from the bridge'
```

Minimal VPS profile:

- Bind the Python bridge to `127.0.0.1:8765` behind a reverse proxy, or `0.0.0.0:8765` only behind a firewall/VPN.
- Set `ECLIPSE_BRIDGE_TOKEN` to a long random value.
- Terminate TLS at the reverse proxy and use an `https://` bridge URL in the Mac app.
- Enter the same bearer token in **Settings → Bridge**.
- Set `ECLIPSE_BRIDGE_DB` so jobs/results survive service restarts.
- Keep this bridge for development only; the SQLite-backed mode is durable enough for MVP testing but not a full production queue.
