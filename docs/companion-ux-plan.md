# Companion UX Plan — Cursor-Native Eclipse

## Status

Ready to begin. The basics are in place:

- Native menu-bar Mac app
- Cursor-positioned overlay
- Accessibility and Screen Recording permission handling
- Active-window context collection
- Window capture path
- Typed bridge job/result protocol
- Local and VPS bridge
- Keychain bridge token storage
- Automatic bridge polling
- Hermes JSON tool host and plugin scaffold
- Context-bound approval for text, key, and click actions
- SQLite outbox/idempotency

The next work is product feel: Eclipse should behave like a Mac companion, not a bridge dashboard.

## Product target

Eclipse should feel close to HeyClicky’s interaction model:

- Lives near the cursor/work
- Understands the active screen
- Lets the user ask by voice
- Responds beside the cursor
- Guides visually before acting
- Requires clear approval for state-changing actions
- Can hand longer work to Hermes agent mode in the background

Eclipse should keep stricter local safety than a demo agent. No silent clicks, typing, credential use, shell execution, or destructive actions.

## Modes

### Ask mode

The user presses/holds a hotkey, asks a question, and gets a short response based on the active window.

Example:

```text
User: what is this settings panel for?
Eclipse: This is the Accessibility permission panel. Eclipse needs it to read the active app/window and validate approved UI actions.
```

### Guide mode

Eclipse explains the next step and points/highlights where to look. It does not click automatically.

Example:

```text
User: where do I enable screen recording?
Eclipse: Open Privacy & Security, then Screen & System Audio Recording. I’ll highlight the row.
```

### Action mode

Hermes proposes a typed action. Eclipse shows an approval card beside the work. The user approves or cancels.

Example:

```text
User: type this into the focused field
Eclipse: Approve typing “...” into Notes?
```

### Agent mode

The user says an explicit agent phrase for background work.

Example:

```text
User: Eclipse agent, research cameras under $1k and make a shortlist.
Eclipse: Started. I’ll keep working in the background and notify you when there’s a result.
```

## Immediate implementation plan

### 2A — Companion shell

- Add a compact cursor-side buddy/orb state separate from the full approval overlay.
- Keep the existing menu-bar app and use `Option-Space` for the cursor buddy.
- Show compact states: idle, listening, thinking, guiding, needs approval, agent running, error.
- Keep full settings/debug surfaces out of the primary experience.
- Added first implementation: `Option-Space` opens a tiny cursor-side buddy. The buddy has an expand control for the larger companion card with an “Ask Hermes” composer and bridge health summary. The Mac packages local screen context for Hermes instead of answering locally.

Exit check: pressing the hotkey shows a small Eclipse companion near the cursor without opening Settings.

### 2B — Push-to-talk input

- Turn the existing Microphone permission from “planned” into an actual push-to-talk path.
- Start with hold-to-speak or press-to-record; no wake word.
- Show live listening/transcribing state in the cursor-side UI.
- Produce text transcript first; spoken response can come after.

Exit check: user can press a hotkey, speak, and see a transcript in Eclipse.

### 2C — Screen-aware ask

- On ask submit, capture current Accessibility context.
- Optionally attach active-window screenshot metadata/capture when Screen Recording is available.
- Send the request to Hermes or a local adapter as: user transcript + active app/window + focused element + optional capture.
- Render the response beside the cursor.

Exit check: “What app/window am I on?” returns a useful answer without opening the bridge settings.

### 2D — Visual guide layer

- Add non-clicking visual hints: pointer, ring, or highlight rectangle.
- Start from Accessibility element role/label, not raw coordinate clicking.
- Do not execute actions from Guide mode.

Exit check: Eclipse can point at or describe a likely button/field while leaving control to the user.

### 2E — Approval intent

- Add a user-visible `intent` or `reason` field to bridge jobs.
- Show the reason on approval cards.
- Keep target-bound validation and expiry.

Exit check: approval cards say both what will happen and why Hermes asked for it.

### 2F — Agent mode

- Add explicit agent command parsing: “Eclipse agent, ...”
- Queue background Hermes tasks separately from immediate Mac actions.
- Show progress/status in the companion UI.
- Add cancel/stop affordance.

Exit check: a background task can start, report status, and be cancelled without blocking the user’s Mac.

### 2G — Always-available reliability

- Add Launch at Login.
- Add WebSocket/push bridge events after polling proves stable.
- Add compact offline/auth-failed indicators.
- Keep polling fallback.

Exit check: after reboot/login, Eclipse starts, connects, and shows whether the Mac is available.

## Next nine steps

1. Build compact cursor buddy/orb UI. ✅ First compact companion card is in place.
2. Add a transcript field and ask composer to the buddy. ✅ Text ask composer is in place; voice transcript comes next.
3. Implement push-to-talk recording behind the existing microphone permission.
4. Send transcript + active context to a local/Hermes ask endpoint.
5. Display assistant responses beside the cursor.
6. Add `intent`/`reason` to bridge jobs and approval cards.
7. Add first visual guide primitive: highlight/point at a matched Accessibility element.
8. Add explicit “Eclipse agent” background task path.
9. Add Launch at Login and compact connection health.

## Non-goals for this phase

- Wake word
- Silent autonomous clicks
- Shell/file mutation tools
- Credential access
- Email/calendar sending
- Full-display continuous recording
- Public distribution/updater
