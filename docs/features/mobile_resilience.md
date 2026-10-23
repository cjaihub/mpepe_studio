# Feature: Mobile Resilience (Sync Engine)

## 1. What it is
A core networking wrapper that traps offline interactions and reconciles them upon reconnection using version vectors.

## 2. Why it exists
To prevent data loss when creators use the app on poor connections, while aggressively preventing stale data from overwriting newer remote data.

## 3. User story
As a user, if I edit a post while in a tunnel, I want it to sync when I reconnect, unless my editor already published a newer version of the post.

## 4. Screens
- Background Sync Indicator.

## 5. Navigation
Headless background process.

## 6. Backend architecture
`SyncEngine` manages `OfflineAction` queues, firing `_executeActionDirectly` comparing `localBaseVersion` vs `getServerEntityVersion`.

## 7. Database
Local queue stores serialized payloads.

## 8. API
Executes writes recursively on reconnect.

## 9. Realtime
Triggers flush upon socket reconnection.

## 10. Permissions
Inherits permissions of the active session context.

## 11. External services
None directly.

## 12. Failure states
Version mismatch explicitly aborts transaction throwing `Stale state conflict`.

## 13. Offline behavior
Core purpose; stores actions up to local storage limit.

## 14. Analytics
Tracks queue depth and sync success rate.

## 15. Security
Prevents rollback injection attacks by enforcing strictly incrementing version checks.

## 16. Tests
Passes `sync_engine_test.dart` confirming protection against stale overwrites.

## 17. Known limitations
No UI intervention yet for resolving merged conflict logic.

## 18. Future improvements
Build a "Resolve Conflict" UI modal for manual merges.
