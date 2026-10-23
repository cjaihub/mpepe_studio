# PHASE 5/6: API CONTRACT

## 1. Outbound Sending (UI -> Repository)
The UI calls `ingestExternalMessage` directly for pessimistic fallback, acting as the local API proxy.
```dart
Future<void> ingestExternalMessage(Conversation conv, InboxMessage msg)
```
- Performs a Firestore transaction.
- Verifies existence via `msgRef` before committing.
- Updates metadata (`updatedAt`) on the parent `Conversation` atomically.

## 2. Inbound Query (Repository -> UI)
```dart
Future<List<InboxMessage>> getMessages(String conversationId, {DocumentSnapshot? startAfter, int limit = 50})
```
- Cursor-based limit queries ensuring unbounded loops are impossible.

## 3. Realtime Stream
```dart
Stream<List<InboxMessage>> watchLatestMessages(String conversationId, {int limit = 20})
```
- The API contract limits the stream cost to the top 20 items. 
