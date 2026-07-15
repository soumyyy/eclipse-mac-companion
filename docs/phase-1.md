# Phase 1 — Native Mac Foundation

## Current increment: Phase 1M

Phase 1A established the native shell. Phase 1B added privacy-filtered local context collection. Phase 1C added active-window capture. Phase 1D added context-bound approval for one controlled text action. Phase 1E added a local mocked bridge contract. Phase 1F added SQLite-backed idempotency and a result outbox. Phase 1G added shared schemas and a local mock bridge API. Phase 1H connected the Mac app to that local bridge over HTTP. Phase 1I added bridge configuration and explicit automatic polling. Phase 1J made the bridge path auth-ready for local or VPS testing. Phase 1K deployed the development bridge on the VPS behind Cloudflare Tunnel. Phase 1L moved bridge tokens to Keychain and removed demo clutter from the visible UI. Phase 1M adds durable SQLite storage to the VPS bridge.

- Menu-bar application named **Eclipse Mac**
- Compact command-style popover and floating overlay
- Global `Option-Space` hotkey
- Explicit assistant UI states
- Live Accessibility, Screen Recording, and Microphone permission status
- Buttons to request access or open the relevant System Settings pane
- Typed context snapshot models
- No remote transport by default; the development bridge URL defaults to localhost
- Active application and focused-window collection through Accessibility
- Focused element role, label, value preview, and selected text
- Secure-field redaction, text truncation, and application/window blocklists
- Local sanitized JSON diagnostics
- ScreenCaptureKit capture bound to the freshly collected window ID and bundle ID
- Ten-second context expiry and capture cancellation when ownership changes
- Memory-only screenshot preview with a 3,840-pixel maximum dimension
- No cursor, window shadow, file export, display capture, or continuous stream
- One approved `ui.set_text` demo action into the currently focused editable text field
- Approval is bound to the original bundle ID, window ID, focused AX element, proposed text, and a ten-second freshness window
- Text mutation is blocked for secure fields, unsupported focused elements, blocked applications, blocked windows, stale approval, and changed focus
- Versioned local bridge job and result envelopes for `context.get_active_window` and `ui.set_text`
- Local risk/input/expiry validation before capability execution
- Mock bridge flow for `ui.set_text`: job received, approval requested, user approves, action receipt produced
- SQLite bridge result store at `Application Support/Eclipse Mac/bridge.sqlite3`
- Idempotency-key replay before capability execution, so duplicate jobs return the stored pending or final receipt
- Local result outbox with posted/unposted tracking; replacing a pending receipt with a final receipt requeues it
- Shared JSON Schema files for jobs, results, approvals, events, heartbeat, and errors
- Example MVP job/result/heartbeat payloads
- Development-only Python mock bridge with create-job, fetch-next-job, receive-result, and replay-outbox endpoints
- Mac app local HTTP client for fetching the next queued bridge job and replaying SQLite outbox receipts
- Overlay controls for manually fetching a local bridge job and posting the result outbox
- Shared ISO-8601 bridge JSON coding between the mock bridge wire protocol and local persistence
- Persisted bridge base URL, defaulting to `http://127.0.0.1:8765`
- Overlay bridge status showing connected, waiting-for-approval, stopped, invalid URL, and unavailable states
- Explicit polling loop that fetches jobs, replays the outbox, waits three seconds on success, and backs off to eight seconds on transport failure
- Optional bearer-token bridge auth in the Mac client and development mock bridge
- `ECLIPSE_BRIDGE_TOKEN`/`--token` support for running the bridge in protected mode
- Minimal VPS deployment profile: HTTPS, token auth, and environment-specific bridge URL
- VPS dev bridge service at `https://bridge.eclipsn.com`, backed by `127.0.0.1:8765` through Cloudflare Tunnel
- Systemd deployment template and operator notes in `deploy/` and `docs/vps-bridge.md`
- Bridge bearer token stored in Keychain, with migration from the previous `UserDefaults` key
- Main overlay focused on bridge status and polling; demo/debug controls moved out of the primary surface
- Durable bridge-side SQLite storage for queued jobs and results via `ECLIPSE_BRIDGE_DB`

## Privacy defaults

- Secure text fields are never read.
- Clipboard access is not implemented.
- Screenshots are on demand and memory-only.
- Full-display and continuous capture are not implemented.
- Microphone permission is visible for planning, but audio capture is not implemented.
- UI mutations require context-bound user approval.

## Manual Phase 1M check

1. Run `python3 bridge/mock_bridge.py --port 8765`.
2. Open the app overlay, confirm the bridge URL is `http://127.0.0.1:8765`, then click **Start Polling**.
3. Create a job with `POST /jobs` using one of the examples in `examples/jobs/`.
4. Wait for the polling loop to fetch it. If the job is `ui.set_text`, review the pending action and approve it.
5. Confirm the outbox is replayed automatically and the mock bridge received the receipt with `GET /results`.
6. Stop the mock bridge and confirm the overlay moves to the unavailable/retry status instead of spinning continuously.
7. Optional auth check: restart the bridge with `ECLIPSE_BRIDGE_TOKEN='dev-token' python3 bridge/mock_bridge.py --port 8765`, enter `dev-token` in the overlay token field, save, and confirm polling still works.
8. Remote check: set the overlay URL to `https://bridge.eclipsn.com`, enter the VPS token from `~/eclipse-mac-bridge/.bridge-token`, save, start polling, and create a remote job through the HTTPS bridge.

## Next increment

Add bridge operator UI/commands for creating remote jobs without using raw `curl`, then start wiring the higher-level companion experience on top of the bridge.

## UI development launch arguments

- `--show-overlay` opens the floating surface immediately.
- `--show-settings` opens the permission dashboard immediately.
- `--capture-window-once` captures one active window in memory, prints only its ID and pixel dimensions, then exits.

These arguments are intended for local visual QA and do not bypass permission checks.
