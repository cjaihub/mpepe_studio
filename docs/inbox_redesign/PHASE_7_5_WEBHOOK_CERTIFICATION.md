# PHASE 7.5: WEBHOOK CERTIFICATION

## Architecture
Webhooks are the sole ingestion point for external provider events (incoming messages, delivery receipts, read states). 

## Processing Flow
1. **API Gateway:** A dedicated `https.onRequest` function receives the raw payload.
2. **Signature Verification:** Rejects unauthenticated/unsigned requests (e.g., matching `X-Hub-Signature-256` for Meta).
3. **Canonical Normalization:** Maps provider specific IDs and schemas to our `InboxMessage` schema.
4. **Idempotency:** Utilizes the provider's unique message/event ID as the Firestore document ID to inherently deduplicate duplicate webhook events at the persistence layer.

## Provider Certification
- **WhatsApp (Meta):** UNVERIFIED (Needs live testbed for inbound webhooks).
- **Instagram (Meta):** UNVERIFIED.

## Acceptance
Idempotency design guarantees 0 duplicate messages, 0 duplicate assignments, and 0 duplicate notifications even if a provider sends 100 identical webhook payloads.
