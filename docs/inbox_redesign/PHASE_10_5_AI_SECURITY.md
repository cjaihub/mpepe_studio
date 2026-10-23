# PHASE 10.5: AI SECURITY

## Security Implementation
- **Zero Client Context Trust:** The `aiCopilotRequest` function completely ignores client-provided conversation history. Context is rebuilt securely from the backend database using strict participant mapping.
- **No Credentials Exposed:** The `OPENROUTER_API_KEY` exists exclusively inside Google Cloud Secret Manager / Firebase defined secrets.
- **Audit Trails:** `userId`, `conversationId`, `action`, `requestId`, and outcome state (`success` / `failed`) are immutably appended to the `ai_audit_logs` collection.
- **Draft Isolation:** AI generated payloads only return to the client memory space as "drafts". They cannot directly bypass the `ControlPlaneService` to trigger canonical sends.
