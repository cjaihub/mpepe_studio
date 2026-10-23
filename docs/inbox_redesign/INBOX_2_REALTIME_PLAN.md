# INBOX 2.0: REALTIME PLAN

## Event Flow
1. External message arrives (e.g., WhatsApp webhook).
2. Cloud Function normalizes to `chats/{id}/messages/{msgId}`.
3. Firestore triggers `onSnapshot` listener on the mobile client.
4. UI updates instantly.

## Optimization
- Do not reload the entire inbox when one message arrives.
- Use Riverpod `select()` to ensure only the specific conversation tile rebuilds when its unread count or last message changes.
- Avoid full list sorts on every tick.

## Live Notifications
- Use FCM (Firebase Cloud Messaging) for background wake-ups.
- Use in-app contextual snackbars (built via `NotificationOverlayManager`) when a high-priority message arrives while the user is inside a different conversation.
