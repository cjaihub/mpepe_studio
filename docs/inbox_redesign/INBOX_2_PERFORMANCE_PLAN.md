# INBOX 2.0: PERFORMANCE PLAN

## Constraints
- Mobile devices have limited memory and battery.
- Rendering a massive list of 1000+ Unified Items and attaching 5 parallel snapshot listeners is highly inefficient.

## Strategy
1. **Virtualized Lists**: Use `ListView.builder` strictly.
2. **Pagination**: Load messages in chunks of 50. Use Firestore cursors (`startAfterDocument`).
3. **Optimistic UI**: When the user sends a message, immediately add it to the local UI state with a `status: MessageStatus.sending`. Reconcile silently when the backend confirms.
4. **Image Caching**: Use robust caching for avatars and attachment thumbnails. Do not re-download images on every scroll.
5. **Debounced Filters**: When typing in the Inbox Search, debounce the input by 300ms before querying the provider/backend.
