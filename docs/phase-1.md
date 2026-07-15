# Phase 1 — Native Mac Foundation

## Current increment: Phase 1V

Phase 1A established the native shell. Phase 1B added privacy-filtered local context collection. Phase 1C added active-window capture. Phase 1D added context-bound approval for one controlled text action. Phase 1E added a local mocked bridge contract. Phase 1F added SQLite-backed idempotency and a result outbox. Phase 1G added shared schemas and a local mock bridge API. Phase 1H connected the Mac app to that local bridge over HTTP. Phase 1I added bridge configuration and explicit automatic polling. Phase 1J made the bridge path auth-ready for local or VPS testing. Phase 1K deployed the development bridge on the VPS behind Cloudflare Tunnel. Phase 1L moved bridge tokens to Keychain and removed demo clutter from the visible UI. Phase 1M added durable SQLite storage to the VPS bridge. Phase 1N added operator commands for creating and inspecting bridge work. Phase 1O added an in-app bridge command composer. Phase 1P added in-app bridge activity/history. Phase 1Q expanded the typed bridge primitives and added the first local command surface. Phase 1R enabled approved `ui.press_key` execution. Phase 1S enabled strict approved `ui.click_element` execution. Phase 1T added Hermes/tool-facing timeout and cancellation behavior. Phase 1U wired queued-job cancellation and fetched-job expiry into the Mac app. Phase 1V adds a concrete JSON Hermes tool host, device heartbeats/presence, copyable activity details, and safer approval countdown UX.

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
- One approved `ui.set_text` action into the currently focused editable text field
- Approval is bound to the original bundle ID, window ID, focused AX element, proposed text, and a ten-second freshness window
- Text mutation is blocked for secure fields, unsupported focused elements, blocked applications, blocked windows, stale approval, and changed focus
- One approved `ui.press_key` action for a small allowed key set: Escape, Return, Tab, Space, Enter, and arrow keys
- Key presses are blocked when the active application/window no longer matches the approval target
- One approved `ui.click_element` action through Accessibility `AXPress`
- Click execution requires the active app/window to match the approval target, an exact element role, an exact element label, and a single matching Accessibility element
- Click execution has no coordinate fallback and blocks risky labels such as Send, Delete, Purchase, Pay, Submit, Checkout, Transfer, and Authorize
- Cancelled approvals produce bridge-visible `rejected` receipts with `user_cancelled`
- Versioned local bridge job and result envelopes for `context.get_active_window`, `context.capture_window`, `notification.show`, `ui.set_text`, `ui.press_key`, and `ui.click_element`
- Local risk/input/expiry validation before capability execution
- Mock bridge flow for `ui.set_text`: job received, approval requested, user approves, action receipt produced
- SQLite bridge result store at `Application Support/Eclipse Mac/bridge.sqlite3`
- Idempotency-key replay before capability execution, so duplicate jobs return the stored pending or final receipt
- Local result outbox with posted/unposted tracking; replacing a pending receipt with a final receipt requeues it
- Shared JSON Schema files for jobs, results, approvals, events, heartbeat, and errors
- Example MVP job/result/heartbeat payloads
- Development-only Python mock bridge with create-job, fetch-next-job, receive-result, and replay-outbox endpoints
- Mac app local HTTP client for fetching the next queued bridge job and replaying SQLite outbox receipts
- Settings controls for bridge configuration, polling, stats, and command composition
- Shared ISO-8601 bridge JSON coding between the mock bridge wire protocol and local persistence
- Persisted bridge base URL, defaulting to `http://127.0.0.1:8765`
- Overlay bridge status showing connected, waiting-for-approval, stopped, invalid URL, and unavailable states
- Explicit polling loop that fetches jobs, replays the outbox, waits three seconds on success, and backs off to eight seconds on transport failure
- Bridge polling starts automatically when the app opens, so the Mac worker is available without manually pressing **Start Polling**
- Optional bearer-token bridge auth in the Mac client and development mock bridge
- `ECLIPSE_BRIDGE_TOKEN`/`--token` support for running the bridge in protected mode
- Minimal VPS deployment profile: HTTPS, token auth, and environment-specific bridge URL
- VPS dev bridge service at `https://bridge.eclipsn.com`, backed by `127.0.0.1:8765` through Cloudflare Tunnel
- Systemd deployment template and operator notes in `deploy/` and `docs/vps-bridge.md`
- Bridge bearer token stored in Keychain, with migration from the previous `UserDefaults` key
- Main overlay focused on bridge status and polling; demo/debug controls moved out of the primary surface
- Durable bridge-side SQLite storage for queued jobs and results via `ECLIPSE_BRIDGE_DB`
- Authenticated bridge inspection endpoints for queued jobs and stats
- Authenticated queued-job cancellation endpoint that removes undelivered jobs and stores rejected cancellation receipts
- Mac Settings activity UI can cancel still-queued bridge jobs through the configured bridge
- Fetched jobs waiting on Mac-side approval now expire locally and post an `expired` receipt through the outbox
- Authenticated heartbeat endpoint for Mac/device presence, persisted by the SQLite bridge
- Mac polling loop posts device presence with status, capabilities, pending job, outbox count, and bridge status
- Settings shows device presence and copyable raw JSON for jobs, results, and devices
- Overlay approvals show live expiry countdowns and disable stale approval buttons
- `bridge/bridge_cli.py` operator CLI for health, stats, jobs, results, context, capture, notification, text, key, and click job creation
- Operator CLI support for `wait-result` and queued-job `cancel`
- Operator CLI support for listing devices and posting a test heartbeat
- In-app command composer for queueing typed jobs to the configured bridge
- Local phrase command box mapping simple commands like `capture window`, `notify Title | Body`, `press escape`, and `type Hello` to typed bridge jobs
- In-app bridge activity panel showing queued jobs and recent remote results from the configured bridge, with expandable details
- Automatic bridge activity refresh after polling/outbox cycles without overwriting the primary bridge status
- `bridge/hermes_adapter.py` thin Hermes-facing scaffold that translates Hermes tool calls into typed bridge jobs, optional result waits, timeout reporting, and queued-job cancellation on timeout
- `bridge/hermes_tool_host.py` JSON-in/JSON-out executable for Hermes-style tool listing and one-shot tool invocation

## Privacy defaults

- Secure text fields are never read.
- Clipboard access is not implemented.
- Screenshots are on demand and memory-only.
- Full-display and continuous capture are not implemented.
- Microphone permission is visible for planning, but audio capture is not implemented.
- UI mutations require context-bound user approval.

## Manual Phase 1V check

1. Run `python3 bridge/mock_bridge.py --port 8765`.
2. Open the app overlay and confirm polling starts automatically against the configured bridge URL.
3. Open **Settings → Bridge** and click **Refresh Activity**.
4. Queue **Active Window**, **Capture Window**, **Press Escape**, or enter `type Hello` in the command box.
5. Wait for the polling loop to fetch it. If the job is `ui.set_text`, review the pending action and approve it. If the job is `ui.press_key`, approve it to post the allowed key event. If the job is `ui.click_element`, approve only when the role/label target is correct.
6. Confirm the outbox is replayed automatically and the mock bridge received the receipt with `GET /results`.
7. Stop the mock bridge and confirm the overlay moves to the unavailable/retry status instead of spinning continuously.
8. Optional auth check: restart the bridge with `ECLIPSE_BRIDGE_TOKEN='dev-token' python3 bridge/mock_bridge.py --port 8765`, enter `dev-token` in Settings → Bridge, save, and confirm polling still works.
9. Remote check: set the bridge URL to `https://bridge.eclipsn.com`, enter the VPS token from `~/eclipse-mac-bridge/.bridge-token`, save, start polling, and queue a remote job from Settings.
10. Operator check: run `python3 bridge/bridge_cli.py stats`, `create-capture-window`, `create-notification`, `create-press-key escape`, and `create-click-element AXButton --element-label Continue` with `ECLIPSE_BRIDGE_URL` and `ECLIPSE_BRIDGE_TOKEN` set.
11. Confirm **Refresh Activity** reflects queued jobs and stored results in the Activity section.
12. Timeout/cancel check: queue a job, run `python3 bridge/bridge_cli.py cancel <job_id>`, and confirm `GET /results/<job_id>` returns a `rejected` cancellation receipt.
13. In-app cancel check: queue a job, refresh **Settings → Bridge → Activity**, expand the queued job, click **Cancel Queued Job**, and confirm the remote result is `rejected` with `cancelled_before_delivery`.
14. Expiry check: fetch a text/key/click job that needs approval, wait past the approval window, then poll once. Confirm the app clears the pending approval, queues an `expired` outbox receipt, and posts it on the next outbox replay.
15. Presence check: while polling, click **Refresh Activity** and confirm **Devices** shows `mac_soumya_local`, status, capabilities, outbox count, and last heartbeat time.
16. Tool host check: run `python3 bridge/hermes_tool_host.py list-tools`, then `python3 bridge/hermes_tool_host.py call mac.get_active_window --wait --timeout-seconds 10` with bridge URL/token configured.
17. Approval UX check: queue a key/text/click job and confirm the overlay shows a countdown and disables approval after expiry.

## Next increment

Wire `bridge/hermes_tool_host.py` into the actual Hermes process/plugin interface when that runtime is available, then add a WebSocket event stream for lower-latency presence, progress, and cancellation.

## UI development launch arguments

- `--show-overlay` opens the floating surface immediately.
- `--show-settings` opens the permission dashboard immediately.
- `--capture-window-once` captures one active window in memory, prints only its ID and pixel dimensions, then exits.

These arguments are intended for local visual QA and do not bypass permission checks.
