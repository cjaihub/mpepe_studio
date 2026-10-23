# PHASE 9: OUTBOX RECOVERY

## Stuck Lease Recovery
If the `processOutboxCommand` worker crashes mid-execution (after marking `SENDING` but before resolving), the command previously risked permanent abandonment.

We have implemented a **Lease pattern**:
1. When transitioning to `SENDING`, the worker generates a `processorId` and sets `leaseExpiresAt = now + 60s`.
2. A new scheduled worker `recoverStuckOutboxLeases` (cron) queries for `status == SENDING` where `leaseExpiresAt < now`.
3. Expired leases are explicitly marked as `UNKNOWN` rather than `FAILED` or `QUEUED`.

## Why UNKNOWN?
If a process crashes while executing an HTTP request to Meta, it is theoretically possible the request succeeded on Meta's end but the acknowledgment failed. Automatically marking it `RETRYABLE` could cause duplicate messages (spam). `UNKNOWN` requires explicit reconciliation (e.g. by a webhook arriving later matching the `idempotencyKey`), completely eliminating the risk of a retry storm.
