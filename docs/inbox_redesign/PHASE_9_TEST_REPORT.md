# PHASE 9: TEST REPORT

## Test Execution Log

### Notifications
- **Pagination Test:** Scrolled to index 20. Clicked "Load older". Verified limit bumped to 40, UI extended cleanly without losing stream state.
- **Deep Link Navigation:** Clicked a 'New Message' notification. Passed `context.push('/conversation/CONV1?anchor=MSG1')`. UI stacked correctly. Pressing Back safely restored Notification list.

### Search
- **Stale Result Rejection:** Rapidly triggered Search A -> Search B. Delayed Search A's backend response. Verified UI completely ignored Search A's payload when it arrived, matching the Nonce requirement.
- **Filter Switching:** Toggled between "Messages" and "People" filters. Verified `executeSearch` instantly re-fired with the new type constraint while preserving the query text.

### Outbox Recovery
- **Lease Expiration Test:** Manually injected an outbox entry stuck in `SENDING` with a `leaseExpiresAt` set to 5 minutes ago. Executed the `recoverStuckOutboxLeases` Firebase function. Verified the outbox entry immediately converted to `UNKNOWN` and explicitly nullified the `nextRetryAt` timestamp to block a retry storm.
