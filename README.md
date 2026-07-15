# Hermes macOS Worker

> The native product is named **Eclipse Mac**. The architecture below retains the
> Hermes worker terminology where it describes the Mac ↔ Hermes boundary.

A native macOS assistant worker connected to Hermes Agent running on a VPS.

The Mac owns local computer access: Accessibility, screen capture, microphone, overlay, approvals, local secrets, and execution. Hermes on the VPS owns planning, memory, scheduling, integrations, and heavier reasoning.

**Core rule:** Hermes proposes. The Mac validates, asks for approval when needed, and executes through typed capabilities.

---

## Architecture

```text
Mac app / worker                         VPS
────────────────────                     ─────────────────────
SwiftUI/AppKit menu app                   Hermes Agent
Overlay + push-to-talk                    Durable memory / planning
Accessibility context                     Webhooks / cron / tools
ScreenCaptureKit fallback                 Remote integrations
Local policy + approvals                  Hermes bridge API
SQLite outbox                             NATS/Redis durable queue
Keychain device creds          <──────>   WS + HTTPS + job queue
```

The Mac must not expose a public listener. It should connect outbound to the VPS over a private/secure channel.

Recommended default stack:

| Area | Choice |
|---|---|
| Mac app | Swift 6 + SwiftUI/AppKit |
| Local context | Accessibility first |
| Visual fallback | ScreenCaptureKit |
| Local storage | SQLite |
| Secrets | macOS Keychain |
| VPS bridge | Python/FastAPI |
| Durable queue | NATS JetStream |
| Realtime events | WebSocket |
| Network privacy | Tailscale + TLS |
| Hermes integration | Custom Hermes tool/plugin first |
| Voice | Push-to-talk later |
| Approvals | Required for all actions initially |

---

## Trust Boundary

Never let arbitrary model text become:

- shell commands
- clicks
- typed text
- file edits
- email sends
- credential access
- browser actions
- destructive actions

All actions must go through a typed tool registry with:

- JSON Schema validation
- risk level
- capability scope
- timeout
- cancellation behavior
- idempotency key
- audit metadata
- defined result/error schema

---

## Repository Layout

```text
hermes-macos-worker/
  macos-app/
    HermesMac/
      App/
      Overlay/
      Permissions/
      Context/
      Tools/
      Transport/
      Policy/
      Storage/
  bridge/
    app/
      main.py
      devices.py
      jobs.py
      websocket.py
      hermes_adapter.py
      auth.py
  schemas/
    job.schema.json
    result.schema.json
    event.schema.json
    approval.schema.json
    heartbeat.schema.json
    error.schema.json
  examples/
    jobs/
    results/
  docs/
    architecture.md
    threat-model.md
    mvp-plan.md
```

---

## MVP Scope

Build only this first:

1. Menu-bar Mac app
2. Permission dashboard
3. Active-window Accessibility snapshot
4. One-window screenshot on demand
5. Secure outbound connection to VPS
6. Durable job/result protocol
7. Hermes bridge
8. Hermes tool for `mac.get_active_window`
9. Local notification tool
10. One approved text action into a known text field
11. SQLite idempotency/outbox
12. Basic logs and diagnostics

---

## Explicitly Excluded From MVP

Do **not** build these yet:

- wake word
- autonomous browser control
- email sending
- filesystem write tools
- shell execution
- calendar mutation
- credential access
- continuous screen recording
- multi-Mac support
- public distribution
- Sparkle updater
- complex memory sync
- full HeyClicky clone

These are distractions until the core Mac ↔ Hermes loop works.

---

## Phase 0: Define the Contract

**Goal:** Define the protocol between the macOS worker, bridge, and Hermes.

### Deliverables

Create shared schemas for:

```text
job.schema.json
result.schema.json
event.schema.json
approval.schema.json
heartbeat.schema.json
error.schema.json
```

### MVP Job Envelope

```json
{
  "job_id": "job_01...",
  "protocol_version": "0.1",
  "device_id": "mac_soumya_air",
  "kind": "context.get_active_window",
  "risk": "read",
  "input": {},
  "expires_at": "2026-07-15T12:00:00Z",
  "idempotency_key": "idem_01..."
}
```

### MVP Job Kinds

```text
context.get_active_window
context.get_accessibility_tree
context.capture_window
ui.click_element
ui.set_text
ui.press_key
notification.show
approval.request
```

### Risk Levels

| Risk | Examples | Default Policy |
|---|---|---|
| `read` | active window title, selected text, screenshot | Allowed if app/window is not blocked |
| `reversible` | open app, focus window, type draft, scroll | Allowed only during active user session |
| `consequential` | send, submit, delete, purchase, terminal command, credential use | Always require confirmation |

### Exit Criterion

A mocked Mac client and mocked VPS bridge can exchange versioned jobs and results locally.

---

## Phase 1: Native Mac Foundation

**Goal:** Get a native Mac shell running with permissions, overlay, and local context collection.

### 1. Swift Menu-Bar App

Use:

- Swift 6
- SwiftUI
- AppKit
- menu-bar lifecycle
- global hotkey
- compact overlay

MVP UI states:

```text
idle
listening
thinking
acting
waiting_for_approval
error
```

Start with text/debug controls. Do not start with full voice.

### 2. Permission Dashboard

Check and explain:

- Accessibility
- Screen Recording
- Microphone
- Start at Login, later

Each permission should show:

```text
status
why needed
button to open System Settings
recheck button
```

### 3. Accessibility Snapshot

Implement:

```text
ContextSnapshot
ActiveApp
ActiveWindow
FocusedElement
VisibleElement
```

Example output:

```json
{
  "snapshot_id": "ctx_01...",
  "captured_at": "2026-07-15T09:00:00Z",
  "active_app": {
    "bundle_id": "com.apple.Safari",
    "name": "Safari"
  },
  "window": {
    "id": 123,
    "title": "Pull request #42"
  },
  "focused_element": {
    "role": "AXTextArea",
    "label": "Comment",
    "value_preview": "Looks good..."
  },
  "selected_text": null,
  "visible_elements": [],
  "screenshot_ref": null,
  "redactions": ["secure_fields", "private_notifications"]
}
```

Privacy rules from day one:

- never read secure text fields
- do not read clipboard unless explicitly requested
- block configured apps/windows
- redact private notifications
- truncate long text
- no continuous screenshots
- screenshots only on demand

### 4. ScreenCaptureKit Fallback

Only capture:

- active window
- selected region
- crop around a relevant element

Do not capture the full display by default.

### 5. Local Tool Executor

Start with read-only tools:

```text
context.get_active_window
context.get_accessibility_tree
context.capture_window
notification.show
```

Then add controlled actions:

```text
ui.set_text
ui.press_key
ui.click_element
```

For the first release, require approval before every click, typed action, or keypress.

### 6. Local SQLite

Use SQLite for:

```text
job receipts
idempotency records
pending results
last server cursor
local audit metadata
permission cache
non-sensitive preferences
```

Use Keychain for:

```text
device private key
refresh token
broker credential
database encryption key, if local history is encrypted
```

### Exit Criterion

The local Mac app can show active window context and execute one approved `ui.set_text` into a known text field.

---

## Phase 2: VPS Hermes Bridge

**Goal:** Build a thin bridge between Hermes and the Mac worker.

Use Python/FastAPI unless there is a strong reason not to. Hermes is Python-native, so avoid adding Node unless needed.

### Bridge Responsibilities

```text
device enrollment
short-lived token minting
job enqueue/dequeue
result ingestion
websocket presence/events
Hermes adapter
audit logs
health checks
```

The bridge should not become another agent.

### Transport

Recommended MVP:

```text
HTTPS API      enrollment, job polling fallback, result POST
WebSocket      presence, progress, cancellation, approval prompts
NATS JetStream durable jobs/results
```

Use Redis Streams only if Redis already exists on the VPS. Do not add Redis just to avoid NATS.

### API Endpoints

```http
POST /devices/enroll
POST /devices/refresh-token
GET  /devices/{device_id}/jobs
POST /devices/{device_id}/results
GET  /ws/devices/{device_id}
POST /hermes/jobs
GET  /health
```

### Exit Criterion

The VPS can enqueue a `context.get_active_window` job, the Mac receives it, the Mac returns a result, and the bridge stores/audits it.

---

## Phase 3: Hermes Integration

**Goal:** Let Hermes treat the Mac as a controlled capability provider.

### Preferred MVP Integration

Create a Hermes tool/plugin exposing:

```text
mac.get_active_window
mac.capture_window
mac.type_text
mac.click_element
mac.show_notification
```

The tool calls the bridge, waits for the result, or returns an async job ID.

### Call Flow

```text
Hermes tool call
  ↓
Bridge creates durable job
  ↓
Mac worker receives job
  ↓
Mac policy engine validates job
  ↓
Mac asks approval if needed
  ↓
Mac executes typed tool
  ↓
Mac returns result
  ↓
Hermes responds
```

Hermes never directly controls the Mac.

### Exit Criterion

In Hermes, this works:

```text
What app is active on my Mac?
```

And Hermes returns the real active app/window from the Mac worker.

---

## Phase 4: Voice

Do not build voice first. Voice creates latency and debugging noise before the control path is proven.

After context and jobs work, add push-to-talk.

### Fast Local Voice Path

```text
Mac microphone → OpenAI Realtime → local tools / delegate_to_hermes
```

Use this for low-latency conversational UX.

### Deterministic Hermes Route

```text
Mac microphone → STT → Hermes → TTS/audio response
```

Use this when you need:

- full transcript
- deterministic policy checks
- long reasoning
- durable memory
- scheduled/background work

The permanent OpenAI API key stays on the VPS. The Mac receives only short-lived Realtime credentials.

### Exit Criterion

Push-to-talk can answer simple questions and delegate complex tasks to Hermes.

---

## Phase 5: Reliability and Privacy

Add only after the vertical slice works.

### Reliability Features

```text
job expiry
idempotency
duplicate job handling
reconnect/backoff
offline outbox
permission revocation handling
audit viewer
diagnostics window
structured JSON logs
```

### Failure Tests

```text
Mac offline
VPS restart
duplicate job
expired job
stale Accessibility snapshot
permission revoked
blocked app/window
malicious job input
```

### Exit Criterion

The system degrades safely. No repeated actions. No action executes against stale context.

---

## First Vertical Slice

Target this first:

```text
Hermes on VPS:
“What window is active on my Mac?”

↓ Hermes tool call

Bridge:
creates context.get_active_window job

↓ durable queue / websocket

Mac:
receives job
checks policy
collects Accessibility snapshot
returns result

↓ result posted back

Hermes:
answers with actual active app/window
```

Second slice:

```text
Hermes:
“type hello into the focused text field”

Mac:
shows approval dialog
user approves
Mac types text
returns result
```

If those two work, the architecture is validated.

---

## Mac-First Workflow

On the Mac:

```bash
mkdir hermes-macos-worker
cd hermes-macos-worker
git init
mkdir -p macos-app bridge schemas examples docs
```

Recommended build order:

```text
1. Write schemas
2. Write mock bridge locally
3. Create Swift menu-bar shell
4. Add permission dashboard
5. Add Accessibility active-window snapshot
6. Connect Mac app to local mock bridge
7. Implement job polling / WebSocket
8. Implement result posting
9. Add first approved action
10. Push repo
```

Then on the VPS:

```bash
git clone <repo-url>
# or, after first clone
git pull
```

Deploy the bridge next to Hermes.

---

## VPS Deployment Shape

On the VPS:

```text
~/hermes-macos-worker/
  bridge/
  schemas/
```

Run the bridge as a service:

```text
hermes-mac-bridge.service
```

The bridge connects to:

```text
Hermes Agent
NATS/Redis
Tailscale/private network
```

The Mac connects outbound. Do not expose the Mac publicly.

---

## Initial Commits

### Commit 1

```text
schemas/
  job.schema.json
  result.schema.json
  event.schema.json
  approval.schema.json
docs/
  architecture.md
  threat-model.md
  mvp-plan.md
bridge/
  minimal mock server
```

Commit message:

```bash
git commit -m "docs: define mac worker protocol and mvp plan"
```

### Commit 2

```text
macos-app/
  Swift menu-bar shell
  overlay states
  permission dashboard stub
```

Commit message:

```bash
git commit -m "feat: add mac menu bar shell"
```

### Commit 3

```text
macos-app/
  Accessibility active-window snapshot
  local debug output
```

Commit message:

```bash
git commit -m "feat: collect active window context"
```

---

## Success Definition

The MVP is successful when Hermes can safely do this:

```text
1. Ask the Mac for active window context.
2. Receive a typed result.
3. Ask to type text into the focused field.
4. Trigger a visible Mac approval prompt.
5. Execute only after approval.
6. Return an audited result.
```

Until this works, do not add fancy voice, wake words, shell tools, or browser automation.

---

## Local Development

Phase 1 is implemented as a native Xcode project generated with XcodeGen.

```bash
xcodegen generate
open EclipseMac.xcodeproj
```

Select the `EclipseMac` target, choose your Apple Developer Team under Signing &
Capabilities, and run the app. Eclipse Mac is a menu-bar utility, so it does not
show a Dock icon. Press `Option-Space` to toggle its local overlay.

See [`docs/phase-1.md`](docs/phase-1.md) for the active increment and privacy
defaults.
