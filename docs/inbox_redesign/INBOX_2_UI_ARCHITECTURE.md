# INBOX 2.0: UI ARCHITECTURE

## Design Philosophy
Mobile-First. The UI must feel like a natural, premium chat application (e.g., WhatsApp, Telegram) rather than a compressed enterprise dashboard.

## View Hierarchy
1. **Inbox List Screen (`InboxMobileScreen`)**
   - **Header**: Platform Selector Dropdown ("All Platforms", "WhatsApp", etc.) and Filter Pills (Unread, Assigned, Priority).
   - **List**: Virtualized list of `Conversation` cards. Each card shows avatar, platform icon indicator, latest message preview, timestamp, and unread badge.
   - **Floating Action Button**: Context-aware (e.g., "New Chat" if on System Platform).

2. **Conversation Screen (`ConversationMobileScreen`)**
   - **App Bar**: Back button, Contact Name, Platform Indicator, Contextual Actions (Call, Assignment).
   - **Message List**: Reverse-scrolling, grouped by date. Supports reactions, attachments, and system messages.
   - **Contextual Composer**: Adapts based on capabilities. Hides camera/voice icons if not supported by the current platform connector.

## Responsive Strategy
- Utilize `LayoutBuilder`.
- If screen width < 800px: Use `InboxMobileScreen` and navigate via `context.push()`.
- If screen width >= 800px: Fallback to existing `InboxDashboardScreen` (Desktop Mode).
