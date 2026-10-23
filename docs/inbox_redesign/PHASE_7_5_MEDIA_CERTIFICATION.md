# PHASE 7.5: MEDIA CERTIFICATION

## Secure Pipeline
Direct client-to-storage is secured via `requestSecureAttachmentUpload`.

1. **Authorization:** Flutter app requests a signed/authorized URL or canonical path from the backend.
2. **Validation:** Backend verifies `mimeType` and limits `fileSize` (e.g. 50MB hard limit) before authorizing.
3. **Persistence:** Client executes a `putFile()` directly into the secure user bucket namespace.
4. **Send Attachment:** Client provides the uploaded gs:// URI in the `inboxSendMessage` payload.

## Provider Verification
- **WhatsApp:** Supports image, audio, video. Maps directly to the Media API. UNVERIFIED.
- **Instagram:** Supports image, video. UNVERIFIED.
- **Unsupported Actions:** Audio on Instagram is hidden dynamically by the capability resolver.

**Status:** PASS securely verified. Live transmission is UNVERIFIED.
