# PHASE 7: NOTIFICATION ARCHITECTURE

## Control Plane Logic
Notifications must route through a unified, external pipeline.

1. **External Webhook:** The external platform pings the API.
2. **Canonical Event:** Webhook translates to a canonical Message/Event.
3. **Deduplication:** Hashing `externalMessageId` handles webhook retries.
4. **Realtime Broadcast:** Data hits Firestore. Mobile realtime streams immediately pick it up if the app is foregrounded and observing the chat.
5. **Push Arbitration:** 
   The backend inspects user configuration. If the app is actively listening to the conversation, the push is swallowed to prevent redundant noise.
   If backgrounded or inactive, FCM (Firebase Cloud Messaging) dispatches a push notification.

## Notification Types
- `NEW_MESSAGE`, `MESSAGE_REPLY`, `MENTION`, `CONNECTOR_HEALTH`

## Foreground Behavior
If the user is inside the conversation when the push happens, no intrusive banner drops down because the localized realtime `ConversationStateProvider` resolves the new message visually in the UI list natively.
