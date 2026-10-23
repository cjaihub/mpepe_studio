# Component & Systems Reuse Map

To ensure the application remains a cohesive single platform, all enterprise extensions MUST build upon the following established systems.

## 1. UI & Theming
- **Theming**: Use `AppTheme` (Black background, Red primary, White typography). Do not introduce new conflicting palettes.
- **Navigation**: Extend `StatefulShellRoute` in `router.dart`. Do not implement custom bottom navigation bars outside of `SharedBottomNavBar`.
- **Global Elements**: Reuse `MobileGlobalDrawer`, `NotificationOverlayManager`, and `CallOverlayManager` rather than creating redundant wrappers.

## 2. Authentication & Identity
- **Provider**: `FirebaseAuth` and `AuthRepository`.
- **Profiles**: Extend existing user profile models rather than creating an isolated "Enterprise Profile" collection.

## 3. Messaging & Inbox
- **Aggregation**: Use `unified_inbox_provider.dart` to combine any new incoming message types (e.g., Enterprise alerts) with the existing stream.
- **Models**: Extend `Conversation` and `Message` models for enterprise functionality (e.g., adding a `isEnterprise` flag) rather than making separate `EnterpriseConversation` classes.

## 4. Real-time & Communication
- **Calling**: Continue using `CallEngineService` (WebRTC). Do not introduce a separate VoIP library for enterprise calls.
- **Notifications**: Rely on `push_notification_service.dart`.

## 5. Security & AI
- **AI Tool Authorization**: Route all new AI capabilities through `AiSecurityGateway` to ensure audit logging and structural validation.
