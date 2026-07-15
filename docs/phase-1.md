# Phase 1 — Native Mac Foundation

## Current increment: Phase 1G

Phase 1A established the native shell. Phase 1B added privacy-filtered local context collection. Phase 1C added active-window capture. Phase 1D added context-bound approval for one controlled text action. Phase 1E added a local mocked bridge contract. Phase 1F added SQLite-backed idempotency and a result outbox. Phase 1G adds shared schemas and a local mock bridge API.

- Menu-bar application named **Eclipse Mac**
- Compact command-style popover and floating overlay
- Global `Option-Space` hotkey
- Explicit assistant UI states
- Live Accessibility, Screen Recording, and Microphone permission status
- Buttons to request access or open the relevant System Settings pane
- Typed context snapshot models
- No network transport and no context leaves the Mac
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

## Privacy defaults

- Secure text fields are never read.
- Clipboard access is not implemented.
- Screenshots are on demand and memory-only.
- Full-display and continuous capture are not implemented.
- Microphone permission is visible for planning, but audio capture is not implemented.
- UI mutations require context-bound user approval.

## Manual Phase 1G check

1. Run `python3 bridge/mock_bridge.py --port 8765`.
2. Create a job with `POST /jobs` using one of the examples in `examples/jobs/`.
3. Fetch it with `GET /jobs/next?device_id=mac_soumya_local`.
4. Post a receipt with `POST /results` or replay a batch with `POST /outbox/replay`.
5. Confirm duplicate result posts return the original stored receipt instead of creating a second result.

## Next increment

Connect the Mac app to the local mock bridge over HTTP: poll or fetch a queued job, execute it through the existing local policy/approval path, and post the SQLite outbox result back to the bridge.

## UI development launch arguments

- `--show-overlay` opens the floating surface immediately.
- `--show-settings` opens the permission dashboard immediately.
- `--capture-window-once` captures one active window in memory, prints only its ID and pixel dimensions, then exits.

These arguments are intended for local visual QA and do not bypass permission checks.
