# Feature: Authoritative Counters

## 1. What it is
A centralized reconciliation engine managing all platform metrics (likes, views, follows) combining optimistic deltas with server truths.

## 2. Why it exists
To prevent the frontend from displaying diverging numbers when requests duplicate, fail, or go offline.

## 3. User story
As a user on a slow connection, if I like a post, I want to see the heart turn red instantly, but if my request actually drops, I want the UI to correct itself.

## 4. Screens
- Universal engagement buttons across Unified List Tab.

## 5. Navigation
Inline UI interactions.

## 6. Backend architecture
`CounterService` manages `CounterEntity` mapping `displayValue` as `serverValue + localDelta`. Tracks idempotency via `_processedTransactions`.

## 7. Database
Server updates execute SQL/NoSQL atomic increments.

## 8. API
Triggers RPC increments with `transactionId`.

## 9. Realtime
Socket pushes update `serverValue` causing immediate visual sync.

## 10. Permissions
Requires authenticated action context.

## 11. External services
None.

## 12. Failure states
Server 500 error instantly triggers local rollback and delta subtraction.

## 13. Offline behavior
Delta stays active visually, transaction enqueues indefinitely.

## 14. Analytics
Logs high-velocity engagement trends.

## 15. Security
Idempotency ledger prevents replay attacks attempting to spam like counts.

## 16. Tests
Passes `counter_service_test.dart` for network rollback and duplicate execution handling.

## 17. Known limitations
Memory ledger resets on app restart, relying on OS persistance.

## 18. Future improvements
Persist the idempotency ledger to local storage.
