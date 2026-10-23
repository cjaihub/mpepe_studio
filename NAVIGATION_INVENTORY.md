# Navigation Inventory

## Routing Framework
- **Package**: `go_router`
- **Location**: `lib/shared/router.dart`
- **Guards**: Most non-auth routes are protected by a `_requireAuth` redirect interceptor.

## Core Navigation Shells (`StatefulShellRoute`)
1. **HubShell**: Home, Inbox, Channels, Analytics, More
2. **YtShell**: Dashboard, Channels, Upload, Settings
3. **VideoShell**: Dashboard, Projects, Equipment, Crew
4. **AudioShell**: Dashboard, Productions, Library, Artists
5. **DesktopRemoteShell**: Remote Control, Chat, Voice (specifically for desktop usage)

## Top-level Routes
- `/auth/*`: Login, signup, pending approval, locked screen.
- `/social_hub/*`: Meta/TikTok connection wizards, Feed, Notifications, Analytics.
- `/inbox/*`: Dashboard, Security, Calling (incoming/active).
- `/settings/*`: Comprehensive user and app settings (Profile, Appearance, Privacy, Security, Automation, etc.).
- `/video/*` & `/audio/*`: Production management tools.
- `/yt/*`: YouTube manager tools.
- `/automations/*`: Workflow builders and history.

## Navigation Patterns
- `globalNavigatorKey` exposed for deep linking from push notifications.
- `SessionRouteObserver` updates the backend with the user's last active route.
