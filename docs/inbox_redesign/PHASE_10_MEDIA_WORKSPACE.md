# PHASE 10: MEDIA WORKSPACE

## Media Architecture
Media is attached directly to the canonical conversation architecture.
- **Unified Media View:** Handled contextually in the Tools sheet. Clicking "Media & Files" will route to a dedicated `MediaWorkspaceScreen` (implementation follows canonical real-data constraints).
- **Security:** Media fetches require the canonical `conversationId` and validate that the `currentUserId` is an active participant in that conversation. Permanent public URLs are completely avoided.
- **Performance:** For large media, previews request scaled thumbnails. The full-resolution file is loaded exclusively upon explicit user interaction (e.g., tapping to enter full screen).
