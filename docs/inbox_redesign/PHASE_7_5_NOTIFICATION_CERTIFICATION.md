# PHASE 7.5: NOTIFICATION CERTIFICATION

## Architecture
Push notifications utilize Firebase Cloud Messaging (FCM). 

## Inbound Flow
1. Canonical `InboxMessage` is created.
2. An event triggers via Firestore Cloud Functions.
3. The function resolves recipient FCM tokens.
4. Multicast Push Notification is dispatched.
5. The device receives the payload containing a `conversationId` for deep linking.

## Deduplication & Guarantees
- Foreground notifications suppress the banner and use internal UI state directly.
- Background/Terminated notifications invoke the native OS push tray.
- If a message is a retry/duplicate captured at the idempotency layer, the Cloud Function *does not trigger* because no new document was created, guaranteeing no duplicate push notifications.

**Status:** PASS internally. External triggers are currently UNVERIFIED pending live webhook integration.
