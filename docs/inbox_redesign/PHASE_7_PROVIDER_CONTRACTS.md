# PHASE 7: PROVIDER CONTRACTS

## Overview
Integration testing covers the primary endpoints of a Platform Connector. These tests define what actions are guaranteed safe.

## Example: WhatsApp Cloud API
- **Authentication**: Long-lived Access Token.
- **Webhook**: Verifies HMAC signatures on inbound message payloads.
- **Capabilities**: Full media pipeline (Audio, Video, Images, Docs), text, interactive templates.
- **Delivery States**: Sent, Delivered, Read, Failed (w/ WhatsApp specific error codes).

## Rate Limiting & Backoff
All connectors must conform to the 429 backoff policy in the Control Plane. Repeated failure to execute pushes the connector state into `RATE_LIMITED`, degrading the available action set for the UI until a cooldown passes.
