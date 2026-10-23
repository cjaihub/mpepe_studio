# PHASE 7: SEARCH ARCHITECTURE

## Objective
Provide a unified, server-side indexed search foundation to prevent querying unbounded message records locally.

## Design
1. **SearchQuery Model:**
   ```dart
   class SearchQuery {
     final String text;
     final String? platformId;
     final String? conversationId;
     final DateTime? startDate;
     final String? cursor;
   }
   ```
2. **SearchResult Normalization:**
   Hits return a canonical result schema linking to the `Conversation` and the exact `MessageId`.

3. **Deep-Linking:**
   Tapping a search hit triggers a route:
   `/conversation/:id?messageAnchor=:messageId`
   The `ConversationStateProvider` resolves the anchor and scrolls to the target block via a `ScrollController`.

4. **Context Constraints:**
   Search applies platform context logic natively. If WhatsApp is chosen in the mobile global inbox filter, the search endpoint bounds the dataset to `connectorId == 'whatsapp'` and ignores cross-platform hits.
