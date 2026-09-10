# Architecture

MPEPE STUDIO is a robust, multi-platform media production and CRM tool.

## Tech Stack
- **Frontend Framework**: Flutter
- **State Management**: Riverpod 3 (using `AsyncNotifier` and `FutureProvider`)
- **Backend & Auth**: Firebase (Authentication, Firestore, Storage)
- **Routing**: GoRouter (declarative routing)

## Directory Structure
- `lib/main.dart` - Application entry point.
- `lib/audio_production/` - Screens and widgets related to audio editing and management.
- `lib/auth/` - Authentication flows including login, signup, and approval screens.
- `lib/backend/` - Core backend logic, services, and Riverpod providers (e.g., `TaskService`, `UserService`, `AuthService`).
- `lib/crm/` - Client relationship management, task assignments, and admin tools.
- `lib/shared/` - Reusable UI components (`MpepeButton`, `MpepeCard`), theming (`AppTheme`), and routing logic (`router.dart`).
- `lib/social_hub/` - Integrations for connecting and monitoring social media platforms.
- `lib/video_production/` - Screens and widgets for video editing flows.

## State Management Approach
The application embraces the modern Riverpod 3 approach:
- Use `AsyncNotifierProvider` for mutable state backed by asynchronous APIs.
- Use `FutureProvider` and `FutureProvider.family` for query-based read-only state.
- Legacy `StateNotifier` classes have been migrated out for better data fetching lifecycles.
