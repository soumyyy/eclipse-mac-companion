# Phase 1 — Native Mac Foundation

## Current increment: Phase 1A

This increment establishes the native shell before local context is collected.

- Menu-bar application named **Eclipse Mac**
- Compact command-style popover and floating overlay
- Global `Option-Space` hotkey
- Explicit assistant UI states
- Live Accessibility, Screen Recording, and Microphone permission status
- Buttons to request access or open the relevant System Settings pane
- Typed context snapshot models
- No network transport and no context leaves the Mac

## Privacy defaults

- Secure text fields are never read.
- Clipboard access is not implemented.
- Screenshots are on demand and memory-only.
- Full-display and continuous capture are not implemented.
- Microphone permission is visible for planning, but audio capture is not implemented.
- UI mutations will require context-bound user approval.

## Next increment: Phase 1B

Implement an Accessibility context collector and JSON diagnostics view. The collector must apply redaction, truncation, and blocked-application policy before returning a snapshot.

## UI development launch arguments

- `--show-overlay` opens the floating surface immediately.
- `--show-settings` opens the permission dashboard immediately.

These arguments are intended for local visual QA and do not bypass permission checks.
