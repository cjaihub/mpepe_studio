# PHASE 9: NAVIGATION IMPLEMENTATION

## Cross-Surface Routing Model
The canonical deep-link structure guarantees predictable routing across the MPEPE Studio app regardless of entry point (Notification Center vs. Search).

## Deep Link Execution
`context.push()` is exclusively utilized rather than `context.go()` when navigating to deep context like a conversation. This preserves the navigation stack, ensuring that when the user presses back, they return to the exact scroll position and filter state of their search or notification view.

### Conversation Anchor Parameters
Navigation payloads are structured to pass `?anchor=$messageId`. This allows the `ConversationMobileScreen` to instantly snap or lazily load until it intersects the requested canonical message ID, ensuring users aren't left stranded at the bottom of a chat when searching for a message from 3 years ago.
