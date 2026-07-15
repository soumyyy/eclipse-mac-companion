# Phase 1 — Native Mac Foundation

## Current increment: Phase 1F

Phase 1A established the native shell. Phase 1B added privacy-filtered local context collection. Phase 1C added active-window capture. Phase 1D added context-bound approval for one controlled text action. Phase 1E added a local mocked bridge contract. Phase 1F adds SQLite-backed idempotency and a result outbox.

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

## Privacy defaults

- Secure text fields are never read.
- Clipboard access is not implemented.
- Screenshots are on demand and memory-only.
- Full-display and continuous capture are not implemented.
- Microphone permission is visible for planning, but audio capture is not implemented.
- UI mutations require context-bound user approval.

## Manual Phase 1F check

1. Open a harmless editable field, such as a blank TextEdit document.
2. Focus the field and press `Option-Space`.
3. Click `Prepare Action`.
4. Confirm the displayed bridge job ID, application, window, field, and exact text.
5. Click `Approve & Type` within ten seconds.
6. Confirm `Hello from Eclipse Mac` appears in the focused field and the overlay shows an outbox count.

## Next increment

Add shared JSON Schema files plus a local mock bridge API that can create jobs and receive/replay outbox results over a local development transport.

## UI development launch arguments

- `--show-overlay` opens the floating surface immediately.
- `--show-settings` opens the permission dashboard immediately.
- `--capture-window-once` captures one active window in memory, prints only its ID and pixel dimensions, then exits.

These arguments are intended for local visual QA and do not bypass permission checks.
