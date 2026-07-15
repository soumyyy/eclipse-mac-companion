# Hermes Mac Tool UX

This is the target user experience for Eclipse Mac as a Hermes-controlled Mac companion.

## Product rule

Hermes should feel like it can inspect or perform one concrete Mac action at a time, while the Mac app remains the visible control point for anything that can change local state.

The user should not need to understand bridge jobs, outbox receipts, idempotency keys, or polling.

## Default user flow

1. The user asks Hermes for something about their Mac.
2. Hermes calls one `mac.*` tool.
3. Read-only tools return the answer directly.
4. Action tools surface a clear approval card on the Mac.
5. The user approves or cancels on the Mac.
6. Hermes receives a final result and answers in plain language.

If approval times out, Hermes should say that nothing ran.

## Tool behavior

By default, Hermes-facing tools wait for completion. This makes the tool call behave like a real user-facing action instead of returning a technical queued-job object.

Async queueing still exists for debugging and advanced flows through `wait=false`.

| Tool | User expectation | Approval |
| --- | --- | --- |
| `mac.get_active_window` | “Tell me what I’m looking at.” | No |
| `mac.capture_window` | “Use my current window as context.” | No for metadata-only capture; stricter review when image/OCR payloads are added |
| `mac.show_notification` | “Remind/notify me on my Mac.” | No |
| `mac.type_text` | “Put this exact text into the focused field.” | Yes |
| `mac.press_key` | “Press this safe key in the current app.” | Yes |
| `mac.click_element` | “Click this specific visible UI element.” | Yes |

## Mac approval surface

When approval is required, Eclipse Mac should bring the approval overlay forward automatically. The card should answer four questions immediately:

- Who is asking: Hermes / Eclipse.
- What will happen: type text, press key, click element.
- Where it will happen: app, window, and target field or element.
- What happens if the user does nothing: it expires and nothing runs.

The approval buttons should use action-specific labels:

- `Approve & Type`
- `Approve & Press Key`
- `Approve & Click`

Cancel should always produce a bridge-visible rejected result so Hermes can explain that the user declined.

## Hermes response language

Hermes should translate tool results into user-facing language:

- Success: “Done — I typed it into Notes.”
- User cancelled: “Cancelled — I didn’t change anything.”
- Timeout: “I didn’t get approval in time, so nothing ran.”
- Stale target: “I blocked it because the active window changed.”
- Policy block: “I can’t click that target safely.”
- Bridge offline: “Your Mac worker is not reachable right now.”

## Useful next UX work

1. Add a user-visible `intent`/`reason` field to bridge jobs so approval cards can say why Hermes wants the action.
2. Add a compact notification when an approval arrives while the overlay is hidden.
3. Add a “last action” summary in the menu-bar popover.
4. Add a safer staged flow for clicking: inspect current window first, then approve a specific role/label target.
5. Add Launch at Login after the approval experience feels reliable.
