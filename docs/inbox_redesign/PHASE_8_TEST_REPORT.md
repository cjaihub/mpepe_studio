# PHASE 8: TEST REPORT

## Test Execution

### T1: Outbox Ledger Deduping
- **Scenario:** Mashing the send button.
- **Result:** First tap generated `clientCommandId`. The Outbox Ledger registered `QUEUED`. Subsequent 10 taps failed to insert into Firestore due to transaction collisions on the commandId. 1 logical canonical message produced.

### T2: Outbox Process Re-Classification
- **Scenario:** Forcing a simulated HTTP 429 response from the Provider.
- **Result:** `processOutboxCommand` successfully parsed the 429 and altered the Ledger status to `RATE_LIMITED`, populating the `nextRetryAt` timestamp. The canonical message updated to `deliveryState: rate_limited`.

### T3: Ambiguous Execution (UNKNOWN)
- **Scenario:** Forcing an HTTP `ECONNABORTED` timeout mid-execution.
- **Result:** `processOutboxCommand` flagged the state as `UNKNOWN` rather than `FAILED`. A local retry trigger recognizes `UNKNOWN` and refuses to send blindly without reconciling via webhook first.

### T4: Notification Stacking
- **Scenario:** Generating the same backend interaction payload 50 times.
- **Result:** Push sent exactly once due to `pushSentAt` timestamp check inside the `sendPushNotification` trigger.

All required structural tests PASS.
