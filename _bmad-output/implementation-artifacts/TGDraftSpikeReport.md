# Draft Preview Technical Spike Report

**Date:** 2026-05-31
**Story:** 32.3 — Typing UX 与 Draft Preview 技术预研
**Outcome:** NOT FEASIBLE via Bot API

## Research Questions

### 1. Can Telegram bots set a draft message in the user's input field?

**Answer: No.** The Telegram Bot API does not expose any method to set or manipulate the draft message in a user's input field. The draft mechanism (`messages.saveDraft` in MTProto) is a client-side feature accessible only through the full Telegram client API (TDLib or MTProto), not the Bot API.

### 2. Does `sendMessage` with `link_preview_options` or `business_connection_id` provide draft-like UX?

**Answer: No.** `link_preview_options` only controls how link previews are rendered in sent messages. `business_connection_id` is part of the Telegram Business API, which allows bots to act on behalf of a business account — a fundamentally different scope from setting a user's draft.

### 3. Can bots use `copyMessage` / `forwardMessage` to simulate draft?

**Answer: Not equivalent.** These methods create visible messages in the chat. They do not populate the input field. The UX would be identical to the existing edit-based streaming approach.

### 4. Is there any undocumented `saveDraft` method in Bot API?

**Answer: No.** The Bot API 7.x documentation (as of 2026-05) does not include any draft-related endpoints. The MTProto `messages.saveDraft` method requires user authentication (bot tokens are not sufficient).

## API Availability Matrix

| Method | Bot API | MTProto | Usable for Draft Preview |
|--------|---------|---------|--------------------------|
| `messages.saveDraft` | Not available | Requires user auth | No |
| `sendMessage` | Available | Available | Not draft (creates message) |
| `editMessageText` | Available | Available | Not draft (edits message) |
| `sendChatAction` | Available | Available | Typing indicator only |
| `business_connection_id` | Business API only | Business API only | Different scope |

## Client Compatibility

Draft messages are entirely client-managed:
- Telegram iOS/Android/desktop clients store drafts locally
- Drafts sync across devices via MTProto (user session, not bot)
- Bots have no access to this mechanism

## Failure Modes

Since the feature is not available, there are no failure modes to enumerate. The typing indicator (implemented separately in this story) provides the best available UX improvement.

## Recommendation

**Skip all draft transport implementation.** The `TGStreamingTransport` enum remains as-is (`.edit` / `.append` / `.off`). No `TGDraftStateStore` or `.draft` transport case is needed.

The typing indicator (AC #1) is the only feasible UX enhancement. For private chats, the edit-based streaming from Story 32.2 combined with periodic typing indicators provides a good user experience.

## References

- Telegram Bot API: https://core.telegram.org/bots/api
- MTProto `messages.saveDraft`: Requires user-level authorization
- Telegram Business API: Separate scope, not applicable to standard bots
