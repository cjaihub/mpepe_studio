# PHASE 12.5A — OMNI CONTEXT HYDRATION

## 1. Overview
This document outlines the changes made to correctly hydrate the `OmniContextNotifier` with the canonical context of the `InboxDashboardScreen`.

## 2. Current Architecture
Before this change, `OmniCommandSheet` relied on an independent fallback `_buildContext()` if no context was explicitly passed, which ignored the global `omniContextProvider`. The dashboard had selection state (`selectedInboxItemProvider`), but didn't push it to the `OmniContextNotifier`.

## 3. Context Source of Truth & Synchronization Boundary
* **Source of Truth:** `selectedInboxItemProvider` (and GoRouter navigation state for the surface).
* **Synchronization Boundary:** `InboxDashboardScreen`. It watches `selectedInboxItemProvider` and immediately creates a resolved `OmniContext` and updates `omniContextProvider`.

## 4. Files Changed
1. `lib/inbox/inbox_dashboard_screen.dart` - Upgraded from `StatefulWidget` to `ConsumerStatefulWidget`. Added an effect in `build()` using `ref.listen` to automatically call `_syncContext(next)` upon conversation selection changes.
2. `lib/features/omni_command/omni_command_sheet.dart` - Updated `_buildContext()` to respect `omniContextProvider`.
3. `test/backend/omni_command/context_hydration_test.dart` - Added to verify all edge cases.

## 5. Data Flow Before
User selects Inbox item -> `selectedInboxItemProvider` updates -> UI renders detail panel.
Omni Command opened -> creates arbitrary local context.

## 6. Data Flow After
User selects Inbox item -> `selectedInboxItemProvider` updates -> `InboxDashboardScreen` intercepts via `ref.listen` -> `OmniContextResolver` generates strict context -> `omniContextProvider` updates.
Omni Command opened -> reads global `omniContextProvider` directly -> AI acts on genuine context.

## 7. Security Considerations
Context hydration only passes IDs (`conversationId`, `platformId`). It does not pass full message objects or tokens. Backend authorization continues to rely on Firebase Auth ID tokens and verifies user ownership of the `conversationId`. An injected `conversationId` cannot bypass the backend's `checkOwnership(conversationId)` logic.

## 8. Race Prevention
Riverpod's `ref.listen` invokes synchronously in the order of state updates. Because `updateContext` happens immediately upon selection, "last writer wins", avoiding race conditions associated with asynchronous `Future` loops.

## 9. Limitations
Currently, context hydration does not track individual message selections (e.g. `messageId`) because the application does not yet expose a global message selection provider. This can be added incrementally without changing the `OmniContext` schema.
