# INBOX 2.0: DISCOVERY REPORT

## A. CURRENT ARCHITECTURE
The application currently uses a monolithic unified inbox approach (`unified_inbox_provider.dart`) pulling from multiple Firestore repositories (`messaging_repository.dart`, `social_inbox_repository.dart`, etc.). Riverpod is used for state management. The UI is built as a desktop-first dashboard (`inbox_dashboard_screen.dart` uses a Sidebar, List Panel, Chat View, and Context Details in a `Row`) which violates mobile-first principles.

## B. EXISTING FUNCTIONALITY
- User-to-user messaging (text, attachments, reactions).
- Social interactions (comments, mentions, likes) across Meta, TikTok, YouTube.
- AI assistant modes (suggest, context, auto).
- Read/unread counts, presence, and typing indicators.
- Global filtering by status and platform.
- Remote connect status (device alerts).

## C. EXISTING REUSABLE COMPONENTS
- `AppTheme` and `AppColors` (brandRed, darkSurface, etc.).
- `PlatformConnector` core abstract class.
- Unified item models (`UnifiedItem`).

## D. EXISTING BACKEND SERVICES
- Firebase Firestore (NoSQL database).
- Firebase Authentication / Google Sign-In.
- Firebase Messaging (FCM for push notifications).
- External capabilities managed via connectors (Meta, TikTok, WhatsApp, YouTube).

## E. EXISTING APIs
- Provider instances like `userChatsProvider`, `notificationsStreamProvider`, `socialMessagesProvider`.
- Platform Connectors handle external API syncing and publishing via their respective implementations.

## F. EXISTING REALTIME
- Firestore snapshots (`.snapshots()`) handle realtime updates for chats, messages, and social interactions.
- FCM handles background push notifications.

## G. EXISTING CONNECTORS
- `PlatformConnector` architecture is already established.
- Supported capabilities include `messagesRead`, `messagesSend`, `commentsRead`, `contentPublish`, `webhooks`, etc.
- Existing connector implementations: Meta, TikTok, WhatsApp, YouTube.

## H. EXISTING DATABASE MODELS
- `ChatModel`: channel, participants, privacyMode, unreadCounts.
- `MessageModel`: text, attachments, senderId, reactions.
- `SocialMessageModel`: platform, interactionType, targetId.
- `UnifiedItem`: In-memory wrapper aggregating chats, social, AI logs, and projects.

## I. EXISTING NAVIGATION
- Global router (`go_router` typically in Flutter, but current app uses a dashboard `Row` pattern for inbox).
- `BottomNavigationBar` and `NavigationRail` configurations exist in the theme but Inbox relies on desktop panels.

## J. CURRENT UI PROBLEMS
- **Desktop-First**: The `InboxDashboardScreen` uses a hard-coded `Row` with panels, which is terrible for mobile.
- **Cognitive Overload**: Everything is shoved into `UnifiedItem` with no clear hierarchical filtering or mobile-friendly progressive disclosure.
- **Fake Unification**: UI tries to render everything on one screen rather than context-switching smoothly.

## K. TECHNICAL DEBT
- Heavy client-side aggregation in `unifiedInboxProvider.dart` that will cause performance issues at scale.
- Mixed responsibilities: UI knows too much about `UnifiedItemType`.

## L. RISKS
- Modifying the existing Firebase structure might break the current legacy web/desktop app.
- Relying purely on Firestore snapshots for a heavy unified inbox can lead to massive document read costs.

## M. REQUIRED MIGRATIONS
- Migrate UI from dashboard layout to a Mobile-First layout (Stacks, Navigation push/pop, Bottom Sheets).
- Shift some aggregation logic to Cloud Functions to save client-side CPU/battery if reads get too high.

## N. PROPOSED FUTURE ARCHITECTURE
- Canonical Backend Data Model -> Cloud Function normalizers -> Firestore -> Riverpod -> Mobile UI.
- Capability-Driven UI: UI elements render conditionally based on `PlatformConnector.getCapabilities()`.

## O. TESTING STRATEGY
- Unit tests for Normalizers and Capability Resolvers.
- Widget tests for the new Mobile-First Conversation Mode.
- Integration tests simulating a webhook -> Firestore -> UI update.

## P. PERFORMANCE STRATEGY
- Virtualized scrolling for message lists.
- Limit `.snapshots()` reads (e.g., limit 50).
- Idempotent deduplication for incoming webhooks.

## Q. SECURITY STRATEGY
- Firestore Rules must restrict read/write to assigned team members and participants.
- Client cannot authorize AI replies directly; must go through secure backend execution.
