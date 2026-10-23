# PHASE 8: DELIVERY LEDGER

## Architecture
The Delivery Ledger ensures exactly-once outbound messaging by decoupling client-side requests from provider API integration. It solves the critical flaw of ambiguous provider outcomes crashing and generating duplicate sends.

## Canonical Outbox Model
```typescript
{
  commandId: string,          // Primary Key = clientCommandId
  messageId: string,
  conversationId: string,
  userId: string,
  connectorId: string,
  platformId: string,
  status: 'QUEUED' | 'SENDING' | 'SENT' | 'DELIVERED' | 'FAILED' | 'UNKNOWN' | 'AUTH_REQUIRED' | 'RATE_LIMITED',
  attempt: number,
  createdAt: Timestamp,
  updatedAt: Timestamp,
  nextRetryAt: Timestamp | null,
  providerMessageId: string | null,
  lastProviderError: string | null,
  idempotencyKey: string,
  version: number,
  payload: {
    content: string,
    attachments: any[]
  }
}
```

## UNKNOWN State Safely Handled
If the provider HTTP request hangs or connection drops after establishing the TCP socket, the ledger records `UNKNOWN`. The system does NOT automatically retry on `UNKNOWN`, requiring explicit reconciliation or webhook matching rather than blindly spamming the recipient.
