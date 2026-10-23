import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/ai_suggestion.dart';
import '../../auth/auth_repository.dart';

class AiComposerService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Ref _ref;

  AiComposerService(this._ref);

  Future<AiSuggestion?> composeMessage({
    required String conversationId,
    required String messageId, // Optional, for editing existing messages
    required AiComposerAction action,
    required String currentText,
  }) async {
    final uid = _ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    try {
      final HttpsCallable callable = _functions.httpsCallable('aiGateway');
      final response = await callable.call(<String, dynamic>{
        'operation': 'composeMessage',
        'data': {
          'conversationId': conversationId,
          'messageId': messageId,
          'action': action.name,
          'currentText': currentText,
        },
      });

      if (response.data != null && response.data['success'] == true) {
        final data = response.data['suggestion'];
        if (data != null) {
           return AiSuggestion.fromMap(Map<String, dynamic>.from(data), data['id'] ?? 'temp_${DateTime.now().millisecondsSinceEpoch}');
        }
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Error: [${e.code}] ${e.message}');
      throw Exception('AI Composer failed: ${e.message}');
    } catch (e) {
      debugPrint('Error calling AI Composer: $e');
      throw Exception('Failed to generate suggestion.');
    }
  }
}

final aiComposerServiceProvider = Provider<AiComposerService>((ref) {
  return AiComposerService(ref);
});
