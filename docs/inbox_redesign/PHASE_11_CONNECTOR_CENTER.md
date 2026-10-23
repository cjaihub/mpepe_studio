# Phase 11: Connector Center

## Objective
Implement a unified UI that allows users to manage their external platform connections, view capabilities, and monitor connection health.

## Architecture
- `ConnectorCenterScreen`: A central dashboard listing all `ConnectedAccount`s.
- `ConnectorProvider`: Handles the logic for managing connections (adding, removing, re-authenticating).
- **No Mock Capabilities**: UI renders capabilities entirely from canonical `PlatformCapability` definitions.
