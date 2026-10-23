# PHASE 5: CONVERSATION ENGINE

## Overview
The Advanced Conversation Engine moves away from retrieving the entire chat history and filtering locally. We designed a `ConversationStateProvider` (a `FamilyNotifier`) parameterized by `conversationId`.

## Core Features
1. **Targeted State Scope:**
   `ConversationState` only contains data for the currently active chat. Memory footprint is strictly limited to the viewed conversation.
2. **Cursor Pagination:**
   Loads an initial batch of latest messages (`limit: 30`). When the user scrolls upward, `ListView.builder` auto-triggers `loadOlderMessages()`, appending historical items without shifting the user's viewport abruptly.
3. **Optimistic Rendering:**
   A local `addOptimisticMessage` method instantly updates the `messages` array while the `CapabilityAwareComposer` dispatches the command to the network.
4. **Ordering & Deduplication:**
   Message merges ensure duplicate `.id` items are ignored or overwritten correctly. Sort order is strictly forced to descending `timestamp` to feed into `ListView.builder(reverse: true)`.

## Integration
- UI consumes state via `ref.watch(conversationStateProvider(conversationId))`.
- No global rebuilds are fired when scrolling inside a chat.
