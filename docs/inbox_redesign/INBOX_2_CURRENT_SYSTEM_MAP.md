# INBOX 2.0: CURRENT SYSTEM MAP

```text
USER
 ↓
FLUTTER UI
 (inbox_dashboard_screen.dart - Hardcoded Row with Panels)
 ↓
STATE / CONTROLLER LAYER
 (unified_inbox_provider.dart - In-memory client-side aggregation)
 ↓
REPOSITORY / API LAYER
 (messaging_repository.dart, social_inbox_repository.dart)
 ↓
BACKEND
 (Firebase Firestore)
 ↓
SERVICES
 (Cloud Functions for webhooks, missing detailed visibility in client)
 ↓
DATABASE
 (chats, messages, social_messages collections)
 ↓
REALTIME
 (Firestore snapshots)
 ↓
CONNECTOR ENGINE
 (platform_connector.dart - Capability architecture)
 ↓
EXTERNAL PROVIDERS
 (WhatsApp, Meta, TikTok, YouTube)
```

## Observations
- The connector engine (`platform_connector.dart`) is surprisingly mature and correctly identifies capabilities.
- The UI layer is highly coupled to desktop layouts and ignores the connector capabilities (rendering everything globally).
- The state layer aggregates data on the client (reading all chats, notifications, and social messages into one massive list), which is unscalable.
