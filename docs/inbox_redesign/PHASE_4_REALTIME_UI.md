# PHASE 4: REALTIME UI

## 1. Selective Rebuilding
- The Global Inbox (`InboxMobileScreen`) relies on `canonicalInboxNotifierProvider`, which locally patches the `conversations` array inside `updateConversationLocally` when a realtime Firestore message triggers a repository hook.
- It leverages the Riverpod `Notifier` to avoid redrawing the entire screen from a cold database hit.

## 2. Conversation Targeted Realtime
- Inside `ConversationMobileScreen`, we introduced a `conversationStreamProvider(conversationId)`.
- This ensures that only the currently open conversation opens an active websocket/snapshot to Firestore.
- It receives instant updates to `Conversation` metadata, unread counts, and priority markers, completely isolated from the Global Inbox's main list to conserve bandwidth and CPU.

## 3. Resilience
- Uses `.when(data: loading: error:)` seamlessly to gracefully transition between loading states without flashing black screens.
