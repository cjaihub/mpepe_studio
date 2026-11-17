// ignore_for_file: avoid_print
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/ai_brain_service.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_assistant_service.dart';
import 'package:oneova/backend/messaging_repository.dart';
import 'package:oneova/shared/audio/ova_vertex_audio_engine.dart';

final chatAgentServiceProvider = Provider<ChatAgentService>((ref) {
  final firestore = FirebaseFirestore.instance;
  final brainService = ref.read(aiBrainProvider);
  final messagingRepo = ref.read(messagingRepositoryProvider);
  final omniAssistant = ref.read(omniAssistantServiceProvider.notifier);
  return ChatAgentService(firestore, brainService, messagingRepo, omniAssistant);
});

class ChatAgentService {
  final FirebaseFirestore _firestore;
  final AIBrainService _brainService;
  final MessagingRepository _messagingRepo;
  final OmniAssistantService _omniAssistant;
  
  StreamSubscription? _chatSubscription;
  String? _activeChatId;
  final Set<String> _processedMessageIds = {};

  ChatAgentService(this._firestore, this._brainService, this._messagingRepo, this._omniAssistant);

  void listenToChat(String chatId) async {
    if (_activeChatId == chatId) return;
    
    _chatSubscription?.cancel();
    _activeChatId = chatId;
    _processedMessageIds.clear();

    final chatDoc = await _firestore.collection('chats').doc(chatId).get();
    if (chatDoc.exists && chatDoc.data() != null) {
      final chatData = chatDoc.data()!;
      final aiModeStr = chatData['aiAccessMode'];
      if (aiModeStr == 'never') {
        return; // Privacy Block: AI access is disabled for this conversation
      }
    }

    _chatSubscription = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(5)
        .snapshots()
        .listen((snapshot) async {
          
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final senderId = data['senderId'] as String;
          final msgId = change.doc.id;
          final text = data['text'] as String;
          final aiModelId = data['aiModelId'] as String?;

          // Ignore messages sent by the AI agent itself
          if (senderId == 'ai_agent') continue;
          
          // Prevent processing old messages repeatedly on initial load
          if (_processedMessageIds.contains(msgId)) continue;
          _processedMessageIds.add(msgId);
          
          // Check if this message was sent very recently (within 5 seconds) 
          // to avoid replying to old history when opening a chat
          final timestamp = data['timestamp'] as Timestamp?;
          if (timestamp != null) {
            final now = Timestamp.now();
            if (now.seconds - timestamp.seconds > 10) continue;
          }

          _processAndReply(chatId, text, aiModelId);
        }
      }
    });
  }
  
  void stopListening() {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _activeChatId = null;
  }

  Future<void> _processAndReply(String chatId, String userText, String? aiModelId) async {
    try {
      final response = await _brainService.processRequest(
        [
          {'role': 'user', 'content': userText}
        ],
        taskType: 'general',
        userContextPrompt: "${_omniAssistant.generateSystemPromptAdditions()}\\n\\nYou are the Oneova Studio Agent. The user is asking you for help. Read the connected computer's context if necessary.",
      );

      if (response is AiTextResponse && response.isDegraded) {
        return; // Do not auto-post offline fallback notices into user chats
      }

      String replyText = '';
      if (response is AiTextResponse) {
        replyText = response.text;
      } else if (response is AiToolCallResponse) {
        replyText = 'Executed background tools.';
      } else {
        replyText = 'Processed command.';
      }
      
      await _messagingRepo.sendMessage(
        chatId,
        'ai_agent',
        replyText,
        
      );

      // Read out loud with natural Vertex AI audio
      await OvaVertexAudioEngine.instance.speak(replyText);

    } catch (e) {
      print("Error processing AI reply: $e");
    }
  }
}
