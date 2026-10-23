# INBOX 2.0: DATABASE PLAN

## Current Schema
- `chats`: System chat documents.
- `social_messages`: Standalone messages from social.

## Target Schema Migration
We must consolidate all conversational interactions into the `chats` / `messages` hierarchy to allow a truly unified Inbox UI without crazy client-side joins.

### Collection: `chats`
**Additions:**
- `platformId`: e.g., `whatsapp`, `meta`, `system`.
- `connectorId`: Link to the specific connected account.
- `priority`: `low`, `normal`, `high`, `urgent`.

### Collection: `chats/{id}/messages`
**Additions:**
- `externalMessageId`: The unique ID from the provider (used for idempotency/deduplication).
- `externalMetadata`: Map containing provider-specific data (e.g., WhatsApp message template details) that shouldn't pollute the canonical model but is needed for the connector to reply.

## Migration Path
- Do NOT delete `social_messages`. Keep it for legacy.
- Introduce a Cloud Function to mirror new incoming social messages into the `chats` format to slowly migrate clients over.
