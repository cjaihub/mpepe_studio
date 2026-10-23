# PHASE 10.5: AI LIVE INTEGRATION

## Copilot Execution Path
An authoritative `aiCopilotRequest` cloud function has been implemented to replace insecure client-proxy routines.

### Flow
1. **Client Request:** Flutter sends `action`, `conversationId`, `selectedMessageId` (if applicable), and `requestId`.
2. **Backend Authentication:** The server verifies `request.auth.uid`.
3. **Authorization & Context Loading:** The backend queries `canonical_inboxes` mapping logic (via the `conversations` collection) to confirm the user is an active participant. It then strictly scopes and fetches context (e.g., last 10 messages for a DRAFT_REPLY or just one message for a TRANSLATE operation) directly from Firestore.
4. **OpenRouter Query:** The OpenRouter key is securely injected server-side.
5. **Audit Logging:** Every AI execution generates an audit log in `ai_audit_logs`.

### Results
Live execution confirms the client cannot coerce the AI into generating text using unauthorized context data.
