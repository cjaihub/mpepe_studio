# Feature: Instrumentation Scrubber

## 1. What it is
A core interceptor for all telemetry logs enforcing a strict privacy boundary against PII and secrets.

## 2. Why it exists
To mathematically prevent developers or AI agents from accidentally leaking user passwords, private messages, or geo-coordinates to external dashboards.

## 3. User story
As a user, I need absolute confidence that if a system crashes while I am typing my password, my password does not get pushed to a developer's error dashboard.

## 4. Screens
- Background pipeline; visually represented in `production_dashboards.md`.

## 5. Navigation
Headless background process.

## 6. Backend architecture
`InstrumentationEngine` logs metrics to an internal array, routing metadata through `_enforcePrivacyScrubber()`.

## 7. Database
Time-series logging endpoints.

## 8. API
Provides internal `logEvent` interface for all microservices.

## 9. Realtime
Socket drop latencies are logged through this engine.

## 10. Permissions
System-level telemetry execution.

## 11. External services
Sentry / Datadog endpoints.

## 12. Failure states
Scrubber triggers `PrivacyViolationException` which destroys the entire payload and actively halts the rogue transaction.

## 13. Offline behavior
Telemetry buffered in SyncEngine.

## 14. Analytics
Provides base data for all operations.

## 15. Security
Strictly hardcodes exclusion lists for `token`, `password`, `latitude`, `private_ai_context` to block data extraction.

## 16. Tests
Passes `instrumentation_engine_test.dart` definitively crushing all token/location/password payloads.

## 17. Known limitations
Sub-string matching might be too aggressive (e.g. blocking a harmless metric named "password_reset_flow_time").

## 18. Future improvements
Regex-based entropy detection to block raw hashes.
