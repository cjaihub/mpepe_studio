# PHASE 6: COMPOSER ARCHITECTURE

## Overview
The `CapabilityAwareComposer` replaces static input shells with an intelligence layer that renders input mechanics dynamically based on actual connector endpoints.

## Operations
1. **Optimistic Sending Workflow:**
   ```dart
   final optimisticMessage = InboxMessage(..., deliveryState: 'sending');
   notifier.addOptimisticMessage(optimisticMessage);
   try {
     await repo.ingestExternalMessage(conv, optimisticMessage.copyWith(deliveryState: 'sent'));
   } catch(e) {
     notifier.markAsError(optimisticMessage.id);
   }
   ```
2. **Capability Resolution:**
   - Instead of static switches for "WhatsApp" vs "Instagram", the Composer inspects `conversation.capabilities`.
   - `supportsAttachments` checks if `attachments` is present in the capability array.
   - `supportsVoice` conditionally displays the microphone button.
3. **Safe Area & Keyboard:**
   The composer resides inside a `SafeArea` and utilizes dynamic flexible fields which elegantly resize upon keyboard spawn without blocking the conversation viewport.
