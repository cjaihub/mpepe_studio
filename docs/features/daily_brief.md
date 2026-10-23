# Feature: Daily Brief

## 1. What it is
An AI-generated Morning and Evening brief aggregating metrics into Fact, Calculation, and Recommendation nodes.

## 2. Why it exists
To provide creators with an actionable overview of their daily performance and backlogs without forcing them to manually dig through analytics panels.

## 3. User story
As a creator, I want to open my app at 7 AM and instantly know my unread messages and estimated time required to clear them.

## 4. Screens
- Daily Brief Modal
- Insight List View

## 5. Navigation
Automatically triggers on app launch if the current hour matches user `timeTarget` settings.

## 6. Backend architecture
`DailyBriefService` queries the `RealSourceConnector` interface, extrapolates data, and binds it via `BriefInsightConfidence`.

## 7. Database
`DailyBrief` logs attached to `userId`.

## 8. API
Connectors query internal module interfaces.

## 9. Realtime
No direct realtime socket, brief generated on request.

## 10. Permissions
User data bound strictly to requester.

## 11. External services
None required.

## 12. Failure states
Falls back to empty brief if data cannot be retrieved.

## 13. Offline behavior
Brief cannot be generated offline; pulls cached brief if available.

## 14. Analytics
Logs generation latency and user engagement (clicks on recommendations).

## 15. Security
Strict separation of data confidence to prevent hallucinations appearing as factual data.

## 16. Tests
Passes `daily_brief_service_test.dart` strictly verifying calculation boundaries.

## 17. Known limitations
Complex calculations currently rely on hardcoded heuristic formulas.

## 18. Future improvements
Inject LLM dynamically for richer recommendation outputs.
