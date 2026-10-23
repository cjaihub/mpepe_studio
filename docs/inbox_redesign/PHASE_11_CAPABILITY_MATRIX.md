# Phase 11: Capability Matrix

## Objective
Centralize the declaration of platform features.

## Principles
- **Single Source of Truth**: The `getCapabilities()` method inside each `PlatformConnector`.
- **UI Logic Prohibited**: The composer and UI components check for `PlatformCapability` presence rather than checking string matches like `platform == 'Instagram'`.
- **Extensibility**: Capabilities cover Content Read, Content Publish, Messaging, Analytics, Webhooks, etc.
