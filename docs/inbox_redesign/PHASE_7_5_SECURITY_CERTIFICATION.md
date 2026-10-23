# PHASE 7.5: SECURITY CERTIFICATION

## Threat Model & Protections

### 1. Identity Forgery
- **Threat:** Client sends `senderId = ADMIN`.
- **Protection:** Backend `inboxSendMessage` ignores client assertions and forces `request.auth.uid`.

### 2. Conversation Hijacking
- **Threat:** Client sends message to an arbitrary `conversationId`.
- **Protection:** Backend verifies `convData.participants.includes(userId)`. Returns 403 Permission Denied.

### 3. Duplicate Flood (Idempotency)
- **Threat:** Client mashes send on a slow connection.
- **Protection:** Backend uses `clientCommandId` as the document primary key. Conflicts return `{ success: true }` without double-processing.

### 4. Malicious Attachment Execution
- **Threat:** Client uploads a 2GB `.exe` disguised as an image.
- **Protection:** `requestSecureAttachmentUpload` enforces a 50MB ceiling natively. Storage Rules reject non-whitelisted MIME types. 

**Status:** PASS. The Control Plane is securely fortified against client-side tampering.
