# Phase 11.5: Webhook Lifecycle Validation

## Registration State
- **Architectural States**: Distinguished between NOT_CONFIGURED, PENDING, REGISTERED, FAILED, EXPIRED, DISCONNECTED.
- **Webhook Routing**: Account routing resolves to the correct canonical `ConnectedAccount` based on provider and external account ID.

## Security Validation
- **Signature Validation**: Backend functions are expected to verify provider-specific HMAC signatures (e.g. Meta, YouTube).
- **Replay Protection**: Built into the webhook normalization logic (idempotency via external ID).

## Live Verification Status
- **Status**: UNVERIFIED
- **Reason**: No live provider webhook events are flowing. We cannot verify signature checks or payload parsing against real data.

**Conclusion**: INTERNAL ARCHITECTURE = PASS, LIVE PROVIDER INTEGRATION = UNVERIFIED.
