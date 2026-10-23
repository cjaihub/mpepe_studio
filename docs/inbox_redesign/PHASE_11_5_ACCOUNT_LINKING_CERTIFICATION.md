# Phase 11.5: Account Linking Certification

## Canonical Identity
- **Source of Truth**: `ConnectorRegistryService` via Firestore path `users/{userId}/connected_accounts`.
- **Identity Key**: `externalAccountId` scoped by `userId` to ensure cross-user isolation.
- **Model Integrity**: `ConnectedAccount` in `connector_models.dart` strips sensitive `credential` data before `toJson()`, ensuring no secrets leak to the client.

## Validation Gates
- **Duplicate Account Linking**: Architecture prevents duplicates by using `externalAccountId` as the document ID in the user's collection (upsert behavior).
- **Cross-User Account Isolation**: Enforced by Firestore Security Rules scoping collections to `users/{userId}`.
- **Server-Side Ownership**: Authoritative, since all writes to `connected_accounts` are handled server-side post-OAuth.

## Live Verification Status
- **Status**: UNVERIFIED
- **Reason**: No real provider credentials available to execute live end-to-end OAuth linking.

**Conclusion**: INTERNAL ARCHITECTURE = PASS, LIVE PROVIDER INTEGRATION = UNVERIFIED.
