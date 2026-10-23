# PHASE 7: CONNECTOR HEALTH

## The `ConnectorHealth` Model
A canonical state model is implemented to represent the health of a platform connector. 

The model tracks:
- `id` (matches the `connectorId`)
- `status` (`connected`, `degraded`, `disconnected`, `rateLimited`, `reauthRequired`, `error`)
- `lastSuccessfulSync`
- `lastWebhookAt`
- `reauthenticationRequired`

## Realtime Status Binding
Instead of polling the backend, `CapabilityAwareComposer` observes `controlPlaneService.watchConnectorHealth(connectorId)`. This streams the live Firestore health document.

## Action Resolution
The `ControlPlaneService` acts as the centralized action resolver. It maps:
`Conversation` + `ConnectorHealth` + `Permissions` -> `List<String> AvailableActions`

If a connector status falls to `degraded` or `disconnected`, the capability matrix dynamically culls abilities like `send_text` or `send_media`, leaving only local operations like `archive`. The UI responds by disabling text input dynamically and explicitly hinting the error state.
