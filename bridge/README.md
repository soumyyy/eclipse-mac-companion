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
- `POST /jobs/{job_id}/cancel`
- `GET /jobs`
- `GET /jobs/next?device_id=mac_soumya_local`
- `POST /results`
- `POST /outbox/replay`
- `GET /results`
- `GET /results/{job_id}`
- `GET /stats`
- `POST /heartbeats`
- `GET /devices`

Without `ECLIPSE_BRIDGE_DB`, the server stores jobs, results, and device heartbeats in memory. With `ECLIPSE_BRIDGE_DB`, queued jobs, results, and latest device heartbeats are stored in SQLite. It validates the same MVP constraints as the Swift local bridge: protocol `0.1`, supported job kinds, risk matching, and required inputs for typed jobs.

The Mac app can also create bridge jobs from **Settings → Bridge**. The command composer supports `context.get_active_window`, `context.capture_window`, `notification.show`, `ui.set_text`, `ui.press_key`, and `ui.click_element`. Text jobs require Mac-side approval before typing. Key jobs require Mac-side approval before posting one of the allowed key events. Click jobs require Mac-side approval, exact Accessibility role/label matching, and pass the local risky-label blocklist before `AXPress`. The same Settings panel can refresh bridge activity to show queued jobs, recent remote results, device presence, copyable raw JSON, cancel still-queued jobs, and post `expired` receipts for fetched jobs whose Mac-side approval window lapses.

Operator CLI:

```bash
export ECLIPSE_BRIDGE_URL='https://bridge.eclipsn.com'
export ECLIPSE_BRIDGE_TOKEN='replace-with-the-vps-token'

python3 bridge/bridge_cli.py health
python3 bridge/bridge_cli.py stats
python3 bridge/bridge_cli.py jobs
python3 bridge/bridge_cli.py results
python3 bridge/bridge_cli.py devices
python3 bridge/bridge_cli.py heartbeat --status polling
python3 bridge/bridge_cli.py create-context
python3 bridge/bridge_cli.py create-capture-window
python3 bridge/bridge_cli.py create-notification 'Hello from Eclipse' --body 'Bridge notification test'
python3 bridge/bridge_cli.py create-set-text 'Hello from the bridge'
python3 bridge/bridge_cli.py create-press-key escape
python3 bridge/bridge_cli.py create-click-element AXButton --element-label Continue
python3 bridge/bridge_cli.py wait-result job_abc --timeout-seconds 30
python3 bridge/bridge_cli.py cancel job_abc --message 'No longer needed'
```

Hermes adapter scaffold:

```python
from hermes_adapter import EclipseMacHermesAdapter

adapter = EclipseMacHermesAdapter()
adapter.get_active_window(wait=True, timeout_seconds=10)
adapter.invoke_tool("mac.type_text", {"text": "Hello"}, timeout_seconds=30)

# Hermes-facing tool calls wait by default. If a wait times out, queued jobs are
# cancelled by default when the Mac has not fetched them yet. The return shape
# includes timed_out and cancellation.
adapter.press_key_with_approval("escape", wait=True, timeout_seconds=10)
```

Hermes-style JSON tool host:

```bash
export ECLIPSE_BRIDGE_URL='https://bridge.eclipsn.com'
export ECLIPSE_BRIDGE_TOKEN='replace-with-the-vps-token'

python3 bridge/hermes_tool_host.py list-tools --pretty
python3 bridge/hermes_tool_host.py heartbeat
python3 bridge/hermes_tool_host.py devices --pretty
python3 bridge/hermes_tool_host.py call mac.get_active_window --timeout-seconds 10 --pretty
python3 bridge/hermes_tool_host.py call mac.press_key --arguments '{"key":"escape"}' --no-wait
```

Minimal VPS profile:

- Bind the Python bridge to `127.0.0.1:8765` behind a reverse proxy, or `0.0.0.0:8765` only behind a firewall/VPN.
- Set `ECLIPSE_BRIDGE_TOKEN` to a long random value.
- Terminate TLS at the reverse proxy and use an `https://` bridge URL in the Mac app.
- Enter the same bearer token in **Settings → Bridge**.
- Set `ECLIPSE_BRIDGE_DB` so jobs/results survive service restarts.
- Keep this bridge for development only; the SQLite-backed mode is durable enough for MVP testing but not a full production queue.
