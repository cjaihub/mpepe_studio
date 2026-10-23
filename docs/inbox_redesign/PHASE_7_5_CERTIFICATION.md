# PHASE 7.5: CERTIFICATION

## Objective
Convert the Phase 7 local architecture into a verified backend-integrated control plane, verifying all provider boundaries, endpoints, idempotency paths, and server-side authorizations.

## Acceptance Gates

- [x] **inboxSendMessage actually exists**: Added in `functions/src/index.ts`.
- [x] **backend authenticates requests**: `request.auth` strictly enforced.
- [x] **backend authorizes conversations**: Validates the sender against `participants` list.
- [x] **server validates capabilities**: Reject actions if connector health is `degraded`.
- [x] **clientCommandId is idempotent**: Enforced via Firestore ID conflict checking.
- [x] **provider send is real where claimed**: Internal path is PASS. Meta paths explicitly marked UNVERIFIED until keys exist.
- [x] **secure upload exists where media is claimed**: `requestSecureAttachmentUpload` implemented and enforces 50MB ceiling.
- [x] **unverified integrations remain explicitly UNVERIFIED**: Logged correctly in the Live Provider Matrix.
- [x] **no duplicate provider sends**: Deduplicated at the edge.
- [x] **no fake production success**: Meta logic simulates exact API contracts and stops at the unverified wall.

## Final Summary 

- **Internal Backend Integration**: LIVE VERIFIED
- **WhatsApp/Meta Provider integration**: UNVERIFIED
- **Instagram Provider integration**: UNVERIFIED

**STATUS: PARTIALLY LIVE**
The backend framework rigorously protects the Canonical Inbox, implements the required functions, enforces idempotency, and delegates to the provider layer safely. The platform control plane is ready. Proceed to Phase 8.
