import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/ai_brain_service.dart';
import '../ova_assistant/services/ova_device_control.dart';
import '../ova_assistant/services/ova_agentic_orchestrator.dart';
import '../ova_assistant/services/ova_thermal_watchdog.dart';

final oneOvaAssistantServiceProvider = Provider<OneOvaAssistantService>((ref) {
  final aiBrain = ref.watch(aiBrainProvider);
  return OneOvaAssistantService(
    aiBrain: aiBrain,
    deviceControl: ref.watch(ovaDeviceControlProvider),
    agenticOrchestrator: ref.watch(ovaAgenticOrchestratorProvider),
    thermalWatchdog: ref.watch(ovaThermalWatchdogProvider),
  );
});

class AISuggestion {
  final String id;
  final String text;
  final String type; // 'whatsapp', 'creative', 'default'
  final String iconType; // 'phone', 'sparkle', 'badge'
  final String? badge; // e.g. 'NEW'

  AISuggestion({
    required this.id,
    required this.text,
    required this.type,
    required this.iconType,
    this.badge,
  });

  factory AISuggestion.fromMap(Map<String, dynamic> map, String docId) {
    return AISuggestion(
      id: docId,
      text: map['text'] ?? '',
      type: map['type'] ?? 'default',
      iconType: map['iconType'] ?? '',
      badge: map['badge'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'type': type,
      'iconType': iconType,
      if (badge != null) 'badge': badge,
    };
  }
}

class AIInteraction {
  final String id;
  final String query;
  final String status; // 'processing', 'completed', 'error'
  final String? response;
  final DateTime? timestamp;

  AIInteraction({
    required this.id,
    required this.query,
    required this.status,
    this.response,
    this.timestamp,
  });

  factory AIInteraction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AIInteraction(
      id: doc.id,
      query: data['query'] ?? '',
      status: data['status'] ?? 'unknown',
      response: data['response'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}

class OneOvaAssistantService {
  final FirebaseFirestore _firestore;
  final AIBrainService? aiBrain;
  final OvaDeviceControl? deviceControl;
  final OvaAgenticOrchestrator? agenticOrchestrator;
  final OvaThermalWatchdog? thermalWatchdog;

  OneOvaAssistantService({
    FirebaseFirestore? firestore,
    this.aiBrain,
    this.deviceControl,
    this.agenticOrchestrator,
    this.thermalWatchdog,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // Stream dynamic context-aware quick suggestion chips for the active user
  Stream<List<AISuggestion>> getSuggestions(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value(const <AISuggestion>[]);
    }
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('ai_suggestions')
        .orderBy('createdAt', descending: true)
        .limit(3)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AISuggestion.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Stream recent interactions / responses for real-time updates from Python backend & AI Lab
  Stream<List<AIInteraction>> getInteractions(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value(const <AIInteraction>[]);
    }
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('ai_interactions')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AIInteraction.fromDoc(doc))
            .toList());
  }

  // Send voice text or text input straight to your Python/Gemini-backed Firestore pipeline
  // and process with AIBrainService (sharing data with Hub AI Lab)
  Future<DocumentReference<Map<String, dynamic>>?> submitCommand(
    String userId,
    String query, {
    bool hasScreenContext = false,
    String? screenBase64,
    String? modelId,
  }) async {
    if (query.trim().isEmpty) return null;

    // Thermal & Battery Watchdog: Guard against CPU looping and overheating
    if (thermalWatchdog != null && !thermalWatchdog!.canProcessCommand()) {
      debugPrint('[OneOvaAssistantService] Command throttled by Thermal Watchdog to protect device thermals.');
      return null;
    }

    final effectiveUid = userId.trim().isEmpty ? 'guest' : userId.trim();
    final data = <String, dynamic>{
      'query': query.trim(),
      'status': 'processing',
      'timestamp': FieldValue.serverTimestamp(),
      'hasScreenContext': hasScreenContext,
    };
    if (modelId != null) {
      data['modelId'] = modelId;
    }
    if (hasScreenContext && screenBase64 != null) {
      data['screenBase64'] = screenBase64;
    }

    final docRef = await _firestore
        .collection('users')
        .doc(effectiveUid)
        .collection('ai_interactions')
        .add(data);

    // 1) Device-control commands run natively through the Ova AccessibilityService.
    final control = deviceControl;
    if (control != null) {
      try {
        final controlResult = await control.execute(query);
        if (controlResult != null) {
          await docRef.update({
            'status': controlResult.ok ? 'completed' : 'error',
            'response': controlResult.message,
            'kind': 'device_control',
            'completedAt': FieldValue.serverTimestamp(),
          });
          await control.showBubble(controlResult.message);
          return docRef;
        }
      } catch (e) {
        debugPrint('[OneOvaAssistantService] Device control error: $e');
      }
    }

    // 2) Otherwise use AIBrainService so both Overlay and AI Lab share the same models!
    final brain = aiBrain;
    if (brain != null) {
      try {
        final messages = [
          {'role': 'user', 'content': query.trim()}
        ];
        final taskType = hasScreenContext
            ? 'vision'
            : ((query.toLowerCase().contains('audio') || query.toLowerCase().contains('voice'))
                ? 'audio'
                : 'general');
        final userContextPrompt = hasScreenContext
            ? 'User provided circled screen context. Give direct, actionable insight.'
            : null;

        brain.processRequest(
          messages,
          taskType: taskType,
          modelId: modelId,
          screenBase64: screenBase64,
          userContextPrompt: userContextPrompt,
        ).then((response) async {
          String responseText = '';
          if (response is AiTextResponse) {
            responseText = response.text;
          } else if (response is AiWidgetResponse) {
            responseText = jsonEncode(response.data);
          } else if (response is AiToolCallResponse) {
            responseText = 'Executed studio tool: ${response.toolCalls.map((c) => c['function']['name']).join(', ')}';
          }

          if (responseText.isNotEmpty) {
            await docRef.update({
              'status': 'completed',
              'response': responseText,
              'completedAt': FieldValue.serverTimestamp(),
            });
            // Fading answer over whatever app is open (no-op if control is disabled).
            final bubbleText = responseText.length > 280 ? '${responseText.substring(0, 280)}…' : responseText;
            control?.showBubble(bubbleText).catchError((_) {});
          }
        }).catchError((err) {
          debugPrint('[OneOvaAssistantService] Error processing via AIBrain: $err');
        });
      } catch (e) {
        debugPrint('[OneOvaAssistantService] Error initiating AIBrain request: $e');
      }
    }

    return docRef;
  }
}

