# Phase 11: OAuth Security

## Objective
Guarantee secure processing, storage, and refresh cycles for third-party OAuth tokens.

## Rules
- **No Client-Side Credentials**: Mobile UI never handles OAuth access or refresh tokens.
- **Secure Storage**: Tokens are kept in Secret Manager or encrypted server-side fields.
- **Strict Scope Verification**: Only requested scopes are accepted.
- **Token Refresh**: Backend services monitor token expiry (e.g. TikTok's 24h) and preemptively refresh credentials via `refreshCredentials` in the respective `PlatformConnector`.
