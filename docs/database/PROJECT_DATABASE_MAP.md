# MPEPE STUDIO Database Map

All data resides in **Cloud Firestore** and follows strict tenant isolation using `uid`.

## Core Collections
1. `users/{uid}`
   - Subcollections: `settings`, `ai_audit_logs`, `telemetry`
2. `messages/{messageId}`
   - Must contain `senderId` and `conversationId`.
3. `conversations/{conversationId}`
   - Must contain `participants` array (ACL).
4. `_search_index/{docId}`
   - Must contain `allowedViewers` array (ACL) to prevent IDOR/BOLA.
5. `registered_computers/{deviceId}`
   - Desktop application encrypted telemetry payload mapping.
