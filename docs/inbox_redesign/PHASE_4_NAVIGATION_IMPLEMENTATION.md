# PHASE 4: NAVIGATION IMPLEMENTATION

## Contextual Navigation Strategy
We implemented `NavigationContextResolver` to decouple the global routing from embedded widgets, creating a deterministic state machine for determining whether bottom navigation should be visible.

### 1. Global Context
- Determined by `resolveContext` returning `NavigationContext.global`.
- Displays standard application routing components (Home, Inbox, Create, Profile).
- Bound to `InboxMobileScreen`.

### 2. Conversation Context
- Handled inside `ConversationMobileScreen`.
- Entering a chat pushes a new route over the Global Inbox.
- Navigation inside relies on standard `Navigator.pop()` or a contextual bottom navigation replacing the global one (Composer replaces standard bottom nav).
- The transition is seamless, avoiding the jitter of "hiding bottom nav on scroll."

### 3. Route Pushing
- Standard `Navigator.of(context).push` is utilized (simulated pending `go_router` final alignment).
- Contextual headers allow safe retreat via the leading `Icons.arrow_back` button.
