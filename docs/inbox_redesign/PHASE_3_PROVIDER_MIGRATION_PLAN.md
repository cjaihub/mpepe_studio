# INBOX 2.0: PHASE 3 PROVIDER MIGRATION PLAN

## 1. Current Provider Responsibilities
- The current `unifiedInboxProvider` (in `lib/backend/unified_inbox_provider.dart`) retrieves 5 different streams (chats, notifications, social, projects, ai_logs) and merges them into a giant array of `UnifiedItem` in-memory on every update.
- It performs client-side sorting and filtering.

## 2. Responsibilities That Move to Repository
- Pagination, sorting, search, and filtering will move to `CanonicalInboxRepository` via the `InboxQuery` object.
- The repository will return standard `Conversation` objects, not a bespoke UI-only wrapper.

## 3. Responsibilities That Move to Backend
- Data merging and normalization from multiple platforms (e.g. social messages vs chats) now happen via Cloud Functions before insertion into Firestore.

## 4. Compatibility Strategy
- **Do not delete `unifiedInboxProvider` or `UnifiedItem` immediately.**
- Create a new, independent Riverpod architecture (`inbox_query_provider` and `canonical_inbox_state_provider`).
- Migrate `InboxMobileScreen` to exclusively use the canonical state.
- Keep legacy desktop components (`chat_view_panel.dart`, `inbox_list_panel.dart`) on the old provider until Phase 4 (UI implementation) dictates they be deprecated or replaced.

## 5. Migration Order
1. Define `CanonicalInboxState` class (Query, Conversations List, Loading State, Pagination cursor).
2. Create `canonicalInboxStateProvider` (Notifier) that listens to `InboxQuery` changes and fetches from `CanonicalInboxRepository`.
3. Implement `fetchNextPage` and `refresh` inside the Notifier.
4. Integrate targeted realtime updates (`watchLatestMessages` or conversation updates) without full-page reloads.
5. Create Phase 3 tests to verify pagination, caching, and state transitions.
6. Issue Certification.

## 6. Dependent Screens (To be migrated eventually)
- `inbox_list_panel.dart`
- `unified_list_tab.dart`
- `interactive_messages_tab.dart`

## 7. Regression Risks
- If we drop the old provider too early, legacy routing could break.
- Missing an edge case in realtime merging could cause conversations to jump around or get duplicated.
