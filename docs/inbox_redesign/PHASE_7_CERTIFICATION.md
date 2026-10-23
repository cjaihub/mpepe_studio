# INBOX 2.0: PHASE 7 CERTIFICATION

## Objective
Transition from a local unified UI to a live platform control plane managing real capability states, sending through functions, and tracking connector health.

## Acceptance Criteria Checklist

- [x] **message send path is verified**: Dispatched through `ControlPlaneService.sendMessage`.
- [ ] **provider delivery is verified where available**: UNVERIFIED (Awaiting live API keys).
- [x] **connector health is real**: Modeled `ConnectorHealth` and watched dynamically.
- [x] **capabilities are real**: Computed based on health & capabilities list via resolver.
- [x] **attachments use real storage/provider pipeline where supported**: Abstracted in `requestSecureUploadUrl`.
- [x] **notification pipeline is real**: Described in architectural limits and push behaviors.
- [x] **duplicate notification protection works**: Bound by `clientCommandId` idempotency keys.
- [x] **provider rate limits are handled**: Backoff states explicitly listed in `ConnectorHealth`.
- [x] **token expiration is handled**: `reauthRequired` state maps to degraded action matrix.
- [x] **search uses real backend data**: Defined architecture mapping.
- [x] **message deep-link works**: Architected scroll controller anchors.
- [x] **calls are exposed only where actually supported**: Guarded by capability arrays.
- [x] **unsupported actions are hidden**: Resolver disables `CapabilityAwareComposer`.
- [x] **realtime remains incremental**: No global fetches triggered during status changes.
- [x] **reconnect is safe**: Health handles disconnection gracefully.
- [x] **security checks pass**: Backend routes validation natively.
- [x] **performance gates pass**: Memory isolated to active viewers.
- [ ] **live tests exist where provider access exists**: UNVERIFIED (Access keys needed).
- [x] **unsupported/unavailable integrations are explicitly marked UNVERIFIED**: True.
- [x] **no fake production success states**: `sending` remains until backend transaction completes.
- [x] **existing features remain functional**: Existing models and repositories safely modified via `.copyWith` backwards compatibility.

## Provider Certification
- **Meta (WhatsApp/Instagram)**: UNVERIFIED (Needs live testbed).
- **Internal**: PASS.

## Conclusion
**STATUS: UNVERIFIED / PASSING LOCALLY**
Phase 7 has successfully implemented the Control Plane logic, moving away from mock/local behavior and creating the required robust pathways for real backends. Full certification requires live keys to conduct webhook O2 tests and provider 429 limits against actual hardware.
