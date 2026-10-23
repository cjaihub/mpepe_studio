# PHASE 4: UI IMPLEMENTATION

## 1. Responsive Integration
- Retained `InboxDashboardScreen` for desktop/web contexts.
- Injected `LayoutBuilder` which routes all constraints `< 800` widths to `InboxMobileScreen`.
- This ensures desktop authentication, routing, and deep linking are maintained seamlessly without parallel data models.

## 2. Advanced Mobile Global Inbox (`InboxMobileScreen`)
- **Header:** Clean AppBar featuring a "Chats" title, search, and more vert actions.
- **Filters:** Horizontally scrollable row including the `PlatformSelectorDropdown` and active filter pills (`Unread`, `Priority`, `Needs Reply`).
- **List:** Integrated `RefreshIndicator` for "pull to refresh" bound directly to `CanonicalInboxNotifier.refresh()`.
- **Items:** Built `ConversationListItem` with progressive disclosure. It extracts the initial letter, dynamically overlays the connector/platform icon (e.g. WhatsApp, Instagram), displays "Unread" badges via standard MPEPE Red (#990000), and formats timestamps intelligently.
- **Pagination:** Automatically triggers `notifier.fetchNextPage()` when scrolling to the bottom, displaying a CircularProgressIndicator.

## 3. Empty States & Loading
- Handled via canonical state boolean `isLoading`. Replaced static loading black screens with standard `CircularProgressIndicator(color: AppColors.mpepeMaroon)`.
- Empty state properly prompts the user with an "inbox_outlined" icon when no conversations match the current `InboxQuery`.

## 4. Platform Selector (`PlatformSelectorDropdown`)
- Built a mobile-friendly bottom sheet to handle dynamic platform switching.
- Triggers `updatePlatform()` on the Canonical state which immediately re-fetches the paginated list, swapping the UI instantly.
