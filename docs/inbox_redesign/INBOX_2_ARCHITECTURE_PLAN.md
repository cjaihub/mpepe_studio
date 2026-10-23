# INBOX 2.0: ARCHITECTURE PLAN

## Overview
The architecture will transition from a flat, client-aggregated desktop dashboard to a deeply layered, capability-driven mobile experience. The architecture ensures that the client only renders what the backend and external connectors authorize.

## Conceptual Layers

### 1. External Ingestion Layer
- Webhooks from WhatsApp, Meta, TikTok, YouTube.
- Connector engine translates external payloads into `UnifiedWebhookEvent`.

### 2. Normalization Layer (Backend)
- Translates `UnifiedWebhookEvent` into `Conversation` and `InboxMessage`.
- Handles idempotency and deduplication.
- Persists to Firestore.

### 3. State Management (Flutter / Riverpod)
- `unified_inbox_provider` is refactored to be pagination-aware.
- Contextual Resolvers check `PlatformConnector` capabilities to expose actions (Reply, React, Voice).

### 4. UI Layer (Mobile-First)
- **Global Inbox**: List of all `Conversation` models, sorted by priority and `lastMessageTime`.
- **Conversation Mode**: Focused view of a single `Conversation`. Top bar shows platform identity. Bottom composer adapts to capabilities.

## Key Changes from V1
- **UI Decoupling**: Flutter will no longer use a `Row` to show sidebar and chat simultaneously. Mobile relies on `context.push()`.
- **Data Deduplication**: All webhook events will be assigned an `externalId` to prevent duplicate renders.
- **Capability-Driven Composer**: The text input field will query the `Connector` to see if `mediaUpload` or `messagesSend` is supported before rendering attachments or send buttons.
