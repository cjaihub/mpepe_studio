# PHASE 5: REALTIME CHAT

## Implementation Details
The realtime architecture avoids redundant full-fetch snapshots by utilizing isolated Firestore listeners on the targeted conversation document and sub-collections.

### Targeted Stream Merge Strategy
- The repository exposes `watchLatestMessages` limited to `20` items.
- The `ConversationStateNotifier` listens to this stream.
- When `latestMessages` fire, `_mergeRealtimeMessages()` executes an algorithmic diff:
  1. Detect new `id` insertions.
  2. Detect `deliveryState` or `content` updates for existing messages.
  3. Push modifications into a `Map<String, InboxMessage>` dictionary for O(1) replacement.
  4. Emit a new `.copyWith` State, pushing the UI to smoothly update only the affected `MessageBubble` widgets.

### Safety
If the user scrolls deep into the chat (`loadOlderMessages()`), incoming Realtime messages are appended smoothly at index `0` (the bottom of the screen) because `ListView` is operating with `reverse: true`. The scroll position is preserved natively by the Flutter framework.
