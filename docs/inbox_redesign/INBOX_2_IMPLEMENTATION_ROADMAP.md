# INBOX 2.0: IMPLEMENTATION ROADMAP

## PHASE 0: Discovery / Architecture
- [x] Inspect existing repository.
- [x] Document models, UI, and connectors.
- [x] Produce architecture plans.

## PHASE 1: Canonical Inbox Data Model
- Update `Conversation` and `InboxMessage` models to support `externalMessageId`, `priority`, and connector metadata.
- Create Firestore index requests for new filters.

## PHASE 2: Backend Normalization (Cloud Functions)
- Map `SocialMessageModel` payloads into `ChatModel` structures on the backend.
- Ensure deduplication using `externalMessageId`.

## PHASE 3: Mobile-First Provider Refactoring
- Refactor `unified_inbox_provider.dart`.
- Transition from "load everything" to cursor-based pagination.

## PHASE 4: UI Architecture - Global Inbox
- Build `InboxMobileScreen`.
- Implement virtualized list, Platform Selector, and Filter Pills.

## PHASE 5: UI Architecture - Conversation Mode
- Build `ConversationMobileScreen` (the WhatsApp-style chat interface).
- Implement Contextual Navigation (hide bottom nav, adapt App Bar).

## PHASE 6: Capability-Aware Composer
- Wire the Composer to `ConnectorRegistry.getCapabilities()`.
- Dynamically toggle media, voice, and text inputs based on the active platform.

## PHASE 7: Contextual Navigation & Dynamic Bottom Bar
- Implement `NavigationContextResolver`.
- Ensure `context.push()` is used for deep views to preserve back functionality.

## PHASE 8: Performance Optimization
- Apply optimistic UI updates for sending messages.
- Add image caching and fine-tune Riverpod `select` to minimize rebuilds.

## PHASE 9: Integration & QA
- End-to-End test: Real Webhook -> Backend Normalizer -> Firestore -> Mobile UI -> User Reply -> Provider API.
- Test failure states and error isolation.

## NEXT STEPS (For the immediate next phase):
The next execution phase should begin **PHASE 1** and **PHASE 3**, specifically updating the models in `lib/backend/inbox/models/` and refactoring `unified_inbox_provider.dart` to support the new mobile-first paradigm.
