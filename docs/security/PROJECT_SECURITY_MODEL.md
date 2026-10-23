# MPEPE STUDIO Security Model

**Primary Constraint**: Never trust the client payload. Never trust the AI payload.

## Defensive Layers
1. **Authentication**: Handled by Firebase Auth. Operations map exclusively to `currentUser?.uid`.
2. **Tenant Isolation**: Cross-user data leaks are mathematically prevented by subcollections (`users/{uid}/...`) and ACL arrays (`allowedViewers: [uid]`).
3. **Mass Assignment**: UI layers (e.g., `ContactProfile`) scrub inbound records of sensitive fields before rendering.
4. **Prompt Injection**: Handled by `AiSecurityGateway`. Untrusted payloads are wrapped in strict delimiters (`[START UNTRUSTED CONTENT]`) and evaluated sequentially.
5. **Privileged Actions**: Governed by `AppModals`. Destructive irreversible actions demand explicit "CONFIRM" string input.
