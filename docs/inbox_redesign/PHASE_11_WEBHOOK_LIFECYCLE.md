# Phase 11: Webhook Lifecycle

## Objective
Define the lifecycle for receiving, authenticating, and processing webhooks from external platforms.

## Architecture
- **Ingress Layer**: A single webhook ingress (or per-platform endpoint) in Cloud Functions.
- **Authentication**: HMAC signature verification matching platform specific secrets (e.g., Meta's App Secret, WhatsApp Hub Verify Token).
- **Routing**: Validated payload is routed to the canonical `NormalizationService`.
- **Idempotency**: Webhook events use external IDs for deduplication during mapping.
