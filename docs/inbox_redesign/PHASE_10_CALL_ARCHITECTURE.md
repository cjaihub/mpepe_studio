# PHASE 10: CALL ARCHITECTURE

## Objective
Provide real call operations natively within the workspace ONLY where supported by the connector API.

## Implementation Details
1. **State:** UI components currently expose 'Audio Call (Unverified)' and 'Video Call (Unverified)' since the underlying real WebRTC / Provider API bindings are pending active credentials in the control plane.
2. **Architecture:** When fully bound, intent triggers a `CALL_AUDIO` command to the `ControlPlaneService`. The system will stream `IDLE -> CONNECTING -> RINGING -> CONNECTED` strictly driven by actual provider webhooks/realtime state.
3. **Notifications:** A missed call will drop a `AppNotification` directly into the Notification Center.
