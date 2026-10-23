# MPEPE STUDIO: Project Database Map

## Core Schema & State Tracking

### 1. Unified Subsystems
- **CounterEntity**: Keyed by `entityId_type`. Authoritative ground truth representing absolute states of user engagement.
- **OfflineAction**: Keyed by `actionId`. Stores serialized payloads and critical `localBaseVersion` markers for concurrency protection.
- **PerformanceTrace**: Time-series immutable records marking strict MS and FPS variations.

### 2. Ephemeral Storage
- **Idempotency Ledger**: In-memory `Set<String>` blocking duplicate `CounterTransactions`.
- **Connector Tokens**: Handled via `TokenExpiryState` preventing network egress when definitively expired.

### 3. Constraints
- AI Agents are strictly denied direct database writes.
- Telemetry arrays actively strip mapped PII columns prior to database flush.
