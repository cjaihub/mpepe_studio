# INBOX 2.0: SECURITY PLAN

## Client vs Server Trust
- Flutter client is completely untrusted.
- The client cannot dictate whether a message is "allowed" to be sent; it can only request to send it.

## Firestore Rules
- Read access to `chats` is restricted to `userId in participants` or `assignedTeamId in user.teams`.
- Write access to `messages` must be validated. Users cannot fake the `senderId`.

## Connector Security
- Access tokens and OAuth credentials live strictly on the backend / Firebase Functions.
- The Flutter client NEVER receives the actual WhatsApp API token. It only receives a capability confirmation.

## AI Authorization
- AI drafts generated locally or via the gateway must not be automatically sent unless the user has explicitly authorized `AiAccessMode.allowed` and the backend verifies it.
