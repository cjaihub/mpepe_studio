import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../backend/firebase_service.dart'; 
import 'omnichannel_upload_engine.dart';

enum AiIntentType {
  generateMetadata,
  checkStatus,
  publish,
  crossPromote,
  unknown
}

class ParsedIntent {
  final AiIntentType type;
  final String? targetTaskId;
  final Map<String, dynamic> generatedMetadata;
  final String rawResponse;

  ParsedIntent({
    required this.type,
    this.targetTaskId,
    this.generatedMetadata = const {},
    required this.rawResponse,
  });
}

class AiUploadAssistant {
  final Ref _ref;

  AiUploadAssistant(this._ref);

  Future<ParsedIntent> processVoiceCommand(String transcript) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('processAiCommand');
      final result = await callable.call({'transcript': transcript});
      
      final data = result.data;
      if (data != null && data['success'] == true) {
        final aiResult = data['result'] as Map<String, dynamic>;
        
        final intentStr = aiResult['intent'] as String?;
        AiIntentType determinedType = AiIntentType.unknown;
        
        switch (intentStr) {
          case 'generateMetadata':
            determinedType = AiIntentType.generateMetadata;
            break;
          case 'checkStatus':
            determinedType = AiIntentType.checkStatus;
            break;
          case 'publish':
            determinedType = AiIntentType.publish;
            _ref.read(omnichannelUploadEngineProvider.notifier).startUploads();
            break;
          case 'crossPromote':
            determinedType = AiIntentType.crossPromote;
            break;
          default:
            determinedType = AiIntentType.unknown;
        }

        return ParsedIntent(
          type: determinedType,
          rawResponse: aiResult['actionable_response'] ?? "I processed your request.",
          generatedMetadata: aiResult['metadata'] as Map<String, dynamic>? ?? {},
        );
      }
      
      return ParsedIntent(
        type: AiIntentType.unknown,
        rawResponse: "I received an empty response from the AI server.",
      );

    } catch (e) {
      return ParsedIntent(
        type: AiIntentType.unknown,
        rawResponse: "Sorry, I had trouble connecting to the AI brain. Error: ${e.toString()}",
      );
    }
  }
}

final aiUploadAssistantProvider = Provider((ref) {
  return AiUploadAssistant(ref);
});
