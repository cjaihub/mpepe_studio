# Feature: Notification Engine

## 1. What it is
A centralized dispatch system routing user alerts (Messages, Security, Content) with support for quiet hours and AI aggregation.

## 2. Why it exists
To prevent alert fatigue, allow overnight muting without missing critical events, and prevent AI from suppressing security alerts.

## 3. User story
As a creator, I want my phone quiet at night, but if a security breach occurs, I want an urgent override alert immediately.

## 4. Screens
- Notification Inbox UI
- Settings > Quiet Hours UI

## 5. Navigation
Push Notification tap -> Unified List Tab -> Target Content.

## 6. Backend architecture
`NotificationEngine` evaluating timestamps against user-defined quiet hour blocks and prioritizing `NotificationPriority.urgent`.

## 7. Database
`NotificationItem` documents partitioned by `userId`.

## 8. API
Internal service boundaries simulating dispatch pushes.

## 9. Realtime
Socket pushes bypassed if quiet hours block the physical device notification.

## 10. Permissions
User auth required.

## 11. External services
APNs / FCM.

## 12. Failure states
Push failure falls back to silent Inbox delivery.

## 13. Offline behavior
Queues locally until network restore.

## 14. Analytics
Logs delivery latency.

## 15. Security
AI is strictly blocked via `AI Block` exception from suppressing `security` alerts.

## 16. Tests
`notification_engine_test.dart` passes quiet hour math and AI block constraints.

## 17. Known limitations
Complex timezone shifting requires background syncs.

## 18. Future improvements
FCM explicit push payload bindings.
