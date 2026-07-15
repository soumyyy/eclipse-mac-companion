# VPS Bridge Deployment

Current dev deployment:

- VPS SSH alias: `e`
- Service: `eclipse-mac-bridge.service`
- App URL: `https://bridge.eclipsn.com`
- Origin bind: `127.0.0.1:8765`
- Public exposure: existing Cloudflare Tunnel
- Auth: bearer token from `~/eclipse-mac-bridge/.bridge-token` on the VPS

The bridge is intentionally dependency-light and uses Python stdlib only. The VPS deployment stores jobs/results in SQLite at `~/eclipse-mac-bridge/bridge.sqlite3`.

## Runtime files on the VPS

```text
~/eclipse-mac-bridge/
  mock_bridge.py
  .env
  .bridge-token
  bridge.sqlite3
```

Systemd unit:

```text
/etc/systemd/system/eclipse-mac-bridge.service
```

Cloudflare ingress route:

```yaml
- hostname: bridge.eclipsn.com
  service: http://127.0.0.1:8765
```

## Useful commands

Check service:

```bash
ssh e 'systemctl status eclipse-mac-bridge.service --no-pager -l'
```

Restart service:

```bash
ssh e 'sudo systemctl restart eclipse-mac-bridge.service'
```

Check public health:

```bash
curl -s https://bridge.eclipsn.com/health
```

Get the app token from the VPS:

```bash
ssh e 'cat ~/eclipse-mac-bridge/.bridge-token'
```

Use that token in the Mac app:

- Open **Settings → Bridge**
- Bridge URL: `https://bridge.eclipsn.com`
- Bearer token: value from `.bridge-token`
- Save
- Start Polling
- Use the command composer to queue context or approved text jobs
- Click **Refresh Activity** to inspect queued jobs and recent bridge results from inside the app

Create a remote test job:

```bash
TOKEN="$(ssh e 'cat ~/eclipse-mac-bridge/.bridge-token')"
curl -s -X POST https://bridge.eclipsn.com/jobs \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"mac_soumya_local","kind":"context.get_active_window","risk":"read","input":{}}'
unset TOKEN
```

Or use the operator CLI:

```bash
export ECLIPSE_BRIDGE_URL='https://bridge.eclipsn.com'
export ECLIPSE_BRIDGE_TOKEN="$(ssh e 'cat ~/eclipse-mac-bridge/.bridge-token')"

python3 bridge/bridge_cli.py health
python3 bridge/bridge_cli.py stats
python3 bridge/bridge_cli.py create-context
python3 bridge/bridge_cli.py create-set-text 'Hello from the bridge'
```

Read remote results:

```bash
TOKEN="$(ssh e 'cat ~/eclipse-mac-bridge/.bridge-token')"
curl -s https://bridge.eclipsn.com/results \
  -H "Authorization: Bearer $TOKEN"
unset TOKEN
```

## Current limitations

- The bridge stores jobs/results in SQLite at `~/eclipse-mac-bridge/bridge.sqlite3`.
- Token is stored locally in Keychain after saving it in the app.
- The VPS disk is already above 90% usage, so avoid installing additional services until it is cleaned up or resized.
- SQLite is acceptable for current single-worker MVP testing; use a real queue/database before supporting multiple writers/workers.
