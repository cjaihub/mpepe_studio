# MPEPE STUDIO Realtime Model

## System Status Lifecycle
Monitored via `SystemStatusService` (`lib/backend/system/system_status_service.dart`).

1. **Heartbeats**: Periodic pings (10s interval) detect silent connection deaths.
2. **Stale States**: >25s without a heartbeat triggers automatic reconnection sequence.
3. **Exponential Backoff**: Failure to connect yields 2s -> 4s -> 8s -> 16s retry delays.
4. **Duplicate Events**: Event ID caching mathematically drops replicated pub/sub webhook frames.
