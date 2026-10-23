import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ova_assistant/services/ova_tool_registry.dart';
import '../ova_assistant/widgets/ova_assistant_sheet.dart';
import '../services/ai_assistant_service.dart';

/// Entry point used across the app to open Ova. Everything opens the single
/// [OvaAssistantSheet]; this keeps the existing call sites working.
class OneOvaAssistantOverlay {
  OneOvaAssistantOverlay._();

  static Future<T?> show<T>(
    BuildContext context, {
    String? userId,
    OneOvaAssistantService? service,
    Uint8List? screenContextBytes,
    String? screenContextLabel,
    bool autoStartVoice = false,
    String? initialPrompt,
    String? activeChatId,
    String? contentId,
    void Function(String text)? onInsertIntoChat,
  }) {
    return OvaAssistantSheet.show<T>(
      context,
      invocation: OvaInvocationContext(contentId: contentId, chatId: activeChatId),
      initialPrompt: initialPrompt,
      // In a chat the prompt is the user's unsent draft: prefill it, don't send it.
      sendInitialPrompt: activeChatId == null,
      screenContextBytes: screenContextBytes,
      screenContextLabel: screenContextLabel,
      autoStartVoice: autoStartVoice,
      onInsertIntoChat: onInsertIntoChat,
    );
  }
}
