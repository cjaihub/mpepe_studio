# PHASE 9: NOTIFICATION CENTER

## Canonical Notification Implementation
The notification center has been updated from a conceptual model to a fully reactive Riverpod interface (`NotificationCenterScreen`). 

## Features Integrated:
1. **Deduplication:** The `NotificationService` groups duplicate notifications locally if multiple alerts share the same `groupId` within the time window.
2. **Cursor Pagination:** Added `notificationLimitProvider`. Scrolling to the bottom renders a "Load older" button which expands the limit dynamically.
3. **Reactive Filters:** Added a `notificationFilterProvider` enabling UI-driven filter queries (Messages, Mentions, Priority, System). These map directly to the `AppNotificationCategory` enums in the Firestore query.
4. **Deep Linking:** Tapping an unread alert parses either `notification.deepLink` or the JSON `payload` block, firing a precise `context.push()` to launch the user deep into the conversation UI anchored to a specific message ID.
