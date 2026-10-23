# Duplication Risk Report

## Objective
Identify architectural patterns where new enterprise features might mistakenly introduce parallel systems, leading to a fragmented user experience.

## High-Risk Areas

### 1. State Management Fragmentation
- **Risk**: Creating parallel state management architectures (e.g., using BLoC or direct setState in new features while the app uses Riverpod).
- **Mitigation**: Strictly enforce Riverpod `Provider` and `ConsumerWidget` usage for all new enterprise screens.

### 2. Dual User Profiles
- **Risk**: Storing enterprise user data in a separate `enterprise_users` collection, forcing the app to query two locations for a user's identity.
- **Mitigation**: Extend the existing `users` collection document with an `enterpriseData` map or subcollection.

### 3. Isolated Notification Centers
- **Risk**: Building a new notification feed exclusively for enterprise alerts, separate from social or chat notifications.
- **Mitigation**: All notifications must flow through the `UnifiedItem` model and be displayed in the existing `UnifiedHubScreen`.

### 4. Separate WebRTC Engines
- **Risk**: Introducing a new streaming protocol for enterprise "meetings" that conflicts with the existing `CallEngineService`.
- **Mitigation**: Extend `CallEngineService` to support multi-party or enterprise features.

### 5. Fragmented Routing
- **Risk**: Bypassing GoRouter for deep links or pushing routes imperatively (`Navigator.push`) which breaks the desktop/mobile unified URL structures.
- **Mitigation**: All new screens must be registered in `router.dart` and accessed via `context.go()` or `context.push()`.
