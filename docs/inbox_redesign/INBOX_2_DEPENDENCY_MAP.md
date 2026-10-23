# INBOX 2.0: DEPENDENCY AND RISK MAP

## PROTECTED EXISTING FUNCTIONALITY
- **Authentication**: `FirebaseAuth` and Session state.
- **Connectors**: Existing OAuth tokens and connected accounts in `platform_connector.dart`.
- **Social Inbox**: Current `social_messages` collection structure must not be dropped.
- **Messaging API**: Existing system chats and team collaboration messages.
- **AI Gateway**: `CJAiAssistantNotifier` and `AiAssistantMode` logic.

## RISK REGISTER BY DOMAIN

### Navigation (HIGH RISK)
Changing from a `Row` dashboard to a Push/Pop mobile architecture might break the Web/Desktop fallback if not properly gated using responsive builders.
*Mitigation*: Use responsive wrappers. Only apply Mobile-First to constrained widths.

### State Aggregation (HIGH RISK)
Refactoring `unified_inbox_provider.dart` to use pagination could break existing realtime assumptions (e.g., unread count calculations).
*Mitigation*: Separate unread count aggregation (metadata document) from message list queries.

### Connectors (LOW RISK)
The existing `PlatformConnector` architecture is solid. We simply need to enforce its `getCapabilities()` in the UI.

### Realtime / Database (MEDIUM RISK)
Changing message indexing to support global platform filters might require new Firestore Composite Indexes.
*Mitigation*: Pre-deploy indexes before releasing the feature.

### Message Normalization (CRITICAL RISK)
Normalizing external webhooks into `InboxMessage` can result in data loss if platform-specific metadata is dropped.
*Mitigation*: Add an `externalMetadata` Map field to `InboxMessage` to retain raw payloads.
