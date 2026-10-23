# PHASE 6: PLATFORM CAPABILITIES

## Architecture
We explicitly banned using hard-coded UI switches (e.g. `if (platform == 'whatsapp')`). Instead, capabilities flow from `PlatformConnector` implementations, into the `Conversation` model metadata via the backend, and are read natively by the Composer.

### Currently Supported Dynamic Markers
- `attachments`: If absent, the composer hides the `+` attachment button.
- `voice`: If absent, the microphone button disappears in favor of a standard layout.

## Benefit
When a new platform is added (e.g., a CRM connector that only allows plain text replies), no UI changes are needed. The backend simply emits an empty capabilities array `[]`, and the `CapabilityAwareComposer` gracefully simplifies itself.
