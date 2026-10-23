# PHASE 8: OUTBOX ARCHITECTURE

## Request Flow
1. **Flutter Client:** Generates `clientCommandId` locally.
2. **Callable `inboxSendMessage`:** Authorizes and validates capabilities. Writes an entry to `outbox/{clientCommandId}` with status `QUEUED`. Simultaneously creates the local Canonical Message so the UI updates instantly. Returns HTTP 200.
3. **Background Trigger `processOutboxCommand`:** A Firestore `onDocumentCreated` trigger detects the `outbox` entry.
4. **Execution:** Updates state to `SENDING`. Executes the HTTP call against the specific Connector's Provider API (e.g. Meta Graph API).
5. **Reconciliation:** Translates the HTTP response into `SENT`, `FAILED`, `RATE_LIMITED` etc. It patches both the `outbox` document AND the core `messages` Canonical document. The UI receives this update automatically via Realtime Streams.

## Retry Policy & Classification
- **PERMANENT:** `FAILED`, invalid message. No retry.
- **RETRYABLE:** e.g., Rate Limiting (429). Schedules `nextRetryAt` utilizing backoff.
- **AMBIGUOUS:** `UNKNOWN`. Holds execution to prevent duplicates.
