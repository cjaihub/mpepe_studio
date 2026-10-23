# Phase 11.5: Capability Verification

## Capability Reconciliation
- **Canonical Source**: `PlatformCapability` enum driven by `ConnectedAccount`.
- **UI Decoupling**: Components check `account.capabilities.contains(...)` instead of hardcoding provider names.

## Verification Matrix
Each capability distinguishes between:
- NOT_SUPPORTED
- SUPPORTED
- VERIFIED
- UNVERIFIED
- TEMPORARILY_UNAVAILABLE
- REAUTH_REQUIRED

## Live Verification Status
- All dynamic capabilities for providers (YouTube, Meta, TikTok) currently fallback to: UNVERIFIED
- Reason: No live tokens exist to query the real provider capability endpoints. 

**Conclusion**: INTERNAL ARCHITECTURE = PASS, LIVE PROVIDER INTEGRATION = UNVERIFIED.
