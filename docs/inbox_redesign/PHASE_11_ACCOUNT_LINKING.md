# Phase 11: Account Linking

## Objective
Establish the flow for securely linking external platform accounts to the user's MPEPE identity.

## Flow
1. User selects "Link New Provider".
2. Platform specific OAuth modal/redirect starts.
3. Backend (via Firebase Callable) processes the authorization code.
4. Backend retrieves access/refresh tokens.
5. `ConnectedAccount` is generated with strict provider IDs and canonical capabilities.
6. Local UI receives realtime database update.
