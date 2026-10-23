# INBOX 2.0: API PLAN

## Current State
Data is retrieved via direct Firestore snapshots (e.g., `_firestore.collection('chats').snapshots()`).

## Required Modifications

### 1. Paginated Queries
- Replace `.snapshots()` for global lists with cursor-based pagination to support large enterprise inboxes.
- Keep `.snapshots()` active ONLY for the single active Conversation view.

### 2. Backend Normalization API (Cloud Functions)
Instead of Flutter assembling `UnifiedItem` from 5 different collections, introduce a Cloud Function:
- **Trigger**: On webhook from WhatsApp/Meta.
- **Action**: Normalize raw payload into a standard `chats` and `messages` document.
- **Benefit**: The mobile app only needs to listen to `chats` and `messages` collections, massively reducing complexity.

### 3. Action Endpoints
Create robust Cloud Functions for actions rather than direct Firestore writes from the client:
- `sendMessage(chatId, payload)`
- `assignConversation(chatId, userId)`
- `updatePriority(chatId, priority)`

This ensures security and allows the backend to dispatch to the correct `PlatformConnector`.
