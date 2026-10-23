# PHASE 10: CONTEXTUAL ACTIONS

## Contextual Action Resolver
The system relies on rendering active capabilities contextually.

### Message Level
Long-pressing a `MessageBubble` computes:
- Is the current user the sender? (Allows Delete/Edit).
- Are we authorized for AI features? (Allows Summarize).
- Are basic clipboard operations allowed? (Allows Copy).

### Workspace Level
Tapping the "More" icon in the `ConversationMobileScreen` AppBar triggers the Conversation Tools sheet. It surfaces higher-order capabilities like Calls and Search.

## Capability-Gated
Actions like 'Delete' are strictly hidden if the message doesn't belong to the user, enforcing UI consistency with canonical backend permissions.
