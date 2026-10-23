# MPEPE STUDIO: Project API Map

## Internal Microservices API Boundaries

| Domain | Service / Endpoint | Description | Auth Required |
|--------|-------------------|-------------|---------------|
| **Notifications** | `NotificationEngine.dispatchNotification` | Evaluates quiet hours and routes urgent/security pushes. | Yes |
| **Briefs** | `DailyBriefService.generateMorningBrief` | Aggregates external connections to compute Fact/Calculation/Recommendation insights. | Yes |
| **Sync** | `SyncEngine.queueAction` | Buffers mutations and validates against strict `localBaseVersion` on execution. | Yes |
| **Performance** | `PerformanceEngine.recordMetric` | Generates system metrics triggering dynamic infrastructure optimization recommendations. | Internal |
| **Instrumentation** | `InstrumentationEngine.logEvent` | Captures generic telemetry after parsing through a strict `PrivacyScrubber`. | Internal |
| **Counters** | `CounterService.submitTransaction` | Enqueues and resolves UI counting logic idempotently across the network. | Yes |
| **Connectors** | `ConnectorHealthService.checkHealth` | Proxies live HTTP status to determine exact API degradation patterns for UI state. | Yes |
