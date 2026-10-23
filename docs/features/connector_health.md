# Feature: Connector Health

## 1. What it is
A live health tracking pipeline verifying external API boundaries (YouTube, X, Stripe) translating raw HTTP codes to operational states.

## 2. Why it exists
To prevent the app from attempting actions on degraded APIs and to prompt users intelligently when tokens require re-authentication.

## 3. User story
As a creator, I want to know if TikTok's API is down *before* I attempt a massive video upload.

## 4. Screens
- Security Center -> Connected Platforms Health Dashboard.

## 5. Navigation
Settings -> Health Status.

## 6. Backend architecture
`ConnectorHealthService` intercepts `TokenExpiryState` and executes raw HTTP `pingProvider` checks to build `ConnectorHealth`.

## 7. Database
Caches `lastSuccessfulSync` and `lastApiError` locally.

## 8. API
Executes generic OPTIONS/GET root pings against external providers.

## 9. Realtime
Can update UI instantly upon webhook health changes.

## 10. Permissions
Requires connected OAuth scopes.

## 11. External services
All third-party platform APIs.

## 12. Failure states
429 sets `rateLimited`, 403 sets `permissionRequired`, 502 sets `degraded`.

## 13. Offline behavior
Defaults to disconnected status.

## 14. Analytics
Logs provider uptime metrics.

## 15. Security
Pre-flight check blocks network requests if token is already expired, preventing API quota burning.

## 16. Tests
Passes `connector_health_test.dart` for correct code mapping.

## 17. Known limitations
Ping assumes root API status reflects specific endpoint status, which isn't always true.

## 18. Future improvements
Endpoint-specific capability degradation tracking.
