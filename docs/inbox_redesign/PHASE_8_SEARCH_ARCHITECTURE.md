# PHASE 8: SEARCH ARCHITECTURE

## Backend-Driven Strategy
Search MUST NOT load all user messages onto the device.

## The Search Schema
The UI sends a `SearchQuery` request encompassing:
- Text string
- Context filters (connector, platform, specific conversation)
- Date range limitations

## Paging & Protection
1. **Debounce:** Flutter `TextField` executes a strict 500ms debounce before transmitting to the backend.
2. **Stale Results:** An incrementing internal `searchNonce` is passed. If the backend returns a response for `nonce: 3`, but the UI is currently on `nonce: 4`, the payload is silently dropped to prevent screen flicker and overwriting the current state.
3. **Canonical Routing:** Search returns partial `Message` schemas carrying the `conversationId` and `messageId`. Tapping navigates utilizing the identical contextual deep-link mechanism as the Notification Center.

## Server Enforcement
Backend validates that the query strictly belongs to the requested `request.auth.uid`. Cross-tenant discovery is impossible.
