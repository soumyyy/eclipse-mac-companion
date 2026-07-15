# Phase 1 — Native Mac Foundation

## Current increment: Phase 1C

Phase 1A established the native shell. Phase 1B added privacy-filtered local context collection. Phase 1C adds active-window capture.

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

## Privacy defaults

- Secure text fields are never read.
- Clipboard access is not implemented.
- Screenshots are on demand and memory-only.
- Full-display and continuous capture are not implemented.
- Microphone permission is visible for planning, but audio capture is not implemented.
- UI mutations will require context-bound user approval.

## Next increment: Phase 1D

Implement context-bound approval and one controlled `ui.set_text` action into a known focused text field.

## UI development launch arguments

- `--show-overlay` opens the floating surface immediately.
- `--show-settings` opens the permission dashboard immediately.
- `--capture-window-once` captures one active window in memory, prints only its ID and pixel dimensions, then exits.

These arguments are intended for local visual QA and do not bypass permission checks.
