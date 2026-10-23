# INBOX 2.0: CONNECTOR ARCHITECTURE

## Core Concept
The system acts as a unified facade over `PlatformConnector` implementations.

## Extension of Existing Design
The current `PlatformConnector` handles connection, authorization, and basic capabilities. We must strictly enforce this at the UI layer.

### Workflow:
1. User taps a conversation.
2. UI reads `Conversation.channel` (e.g., `SocialPlatform.whatsapp`).
3. UI queries `ConnectorRegistry.get(SocialPlatform.whatsapp).getCapabilities()`.
4. UI resolves list: `[messagesSend, messagesRead, mediaUpload]`.
5. UI builds composer enabling text input and image attachment, but hides Voice Memo button (if missing).

## Connector Interface Enhancements
No major backend structural changes are required for the connectors themselves, as `PlatformConnector` already supports capabilities. We only need to implement robust mapping between `UnifiedItem` and connector-specific outgoing actions.
