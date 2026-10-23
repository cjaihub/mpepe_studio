# PHASE 12.5A — RESEARCH

## 1. Riverpod Notifier and Providers
* **Research question:** How to synchronize state between a generic object (`omniContextProvider`) and a route-specific UI state (`selectedInboxItemProvider`).
* **Conclusion:** `omniContextProvider` uses a mutable `Notifier` designed to be explicitly told by the current route what the context is. It does NOT automatically watch other providers. Therefore, the boundary screen (`InboxDashboardScreen`) should act as the coordinator: listening to `selectedInboxItemProvider` and calling `omniContextProvider.notifier.updateContext()`. This aligns with the "context synchronization layer" requirement.
* **Race conditions:** Riverpod's `ref.listen` executes synchronously immediately after the provider updates. Updating `omniContextProvider` directly avoids async gaps, providing robust stale-context race protection automatically.

## 2. Default copyWith() behavior in Dart
* **Research question:** How to clear fields like `conversationId` via standard copyWith.
* **Conclusion:** The standard `copyWith` idiom in Dart (`field: field ?? this.field`) ignores explicit `null` arguments. We must instantiate a new `OmniContext` explicitly with the cleared fields instead of using `copyWith`.

## 3. FirebaseAuth and User Identity
* **Research question:** How to associate `userId` in `omniContextProvider`.
* **Conclusion:** It must rely on `FirebaseAuth.instance.currentUser?.uid`, avoiding hardcoded user strings in production context mapping.
