# PHASE 8: NOTIFICATION CENTER

## Core Principle
The Notification Center aggregates canonical events (mentions, priority messages, system alerts). It does NOT duplicate data, it relies on Canonical Event identities.

## Event Deduplication Guarantee
- Foreground vs. Background: The FCM trigger verifies if `pushSentAt` already exists to prevent duplicate push requests for the exact same event.
- Same `event_id` from a provider webhook directly targets the identical Firestore document, triggering the `onDocumentCreated` exactly once.

## UI Coherence
- **Color Palette:** STRICT adherence to Red `#990000`, Black `#0A0A0A`, White `#FFFFFF` and `GoogleFonts.inter`.
- **Deep Linking:** Clicking an unread Notification entry extracts the `conversationId` and `messageId` and pushes the route `/conversation/:id?anchor=:messageId`.
- **State:** Tapping "Mark All As Read" triggers a batch backend call to zero the priority state physically, not just hiding the UI badge.
