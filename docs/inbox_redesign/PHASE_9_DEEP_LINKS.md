# PHASE 9: DEEP LINKS & NAVIGATION

## Cross-Surface Deep Linking
The system no longer traps users in silos.

- **From Notifications:** A payload like `{ conversationId: "C1", messageId: "M1" }` correctly routes the `context.push('/conversation/C1?anchor=M1')`.
- **From Search:** A `SearchResult` of type `message` extracts the metadata and routes accurately to the anchored message, allowing the user to seamlessly jump from global search into historical context.
- **State Preservation:** Because we utilize `context.push` via `go_router`, hitting the device Back button safely pops the stack, returning the user exactly to their Search results or Notification list without resetting state.
