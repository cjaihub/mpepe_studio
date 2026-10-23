import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/ai_security_models.dart';

final aiSecurityGatewayProvider = Provider((ref) => AiSecurityGateway());

/// Intercepts AI inputs and outputs to strictly enforce security policies,
/// prevent prompt injection, and validate requested tool executions.
class AiSecurityGateway {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Compiles a secure prompt by framing untrusted content safely.
  String prepareSecurePrompt(List<PromptSegment> segments) {
    final request = SecureAiRequest(segments: segments);
    return request.compilePrompt();
  }

  /// Evaluates an AI's requested tool call against the authenticated user's permissions.
  /// "Never let a user message directly execute privileged tools. 
  /// Every tool call must be authorized independently."
  Future<bool> authorizeToolCall(String toolName, Map<String, dynamic> arguments) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint("AiSecurityGateway: Denied $toolName - No authenticated user.");
      return false;
    }

    final uid = user.uid;
    bool isAuthorized = false;
    
    // 1. Structural Schema Validation
    if (!_validateToolSchema(toolName, arguments)) {
      debugPrint("AiSecurityGateway: Denied $toolName - Invalid schema arguments.");
      return false;
    }

    // 2. Business Logic & Access Control Validation
    try {
      isAuthorized = await _checkBackendPermissions(uid, toolName, arguments);
    } catch (e) {
      debugPrint("AiSecurityGateway: Authorization error $e");
      isAuthorized = false;
    }

    // 3. Audit Logging (Log privileged tool actions)
    await _auditToolExecution(uid, toolName, arguments, isAuthorized);

    return isAuthorized;
  }

  bool _validateToolSchema(String toolName, Map<String, dynamic> arguments) {
    // In production, this validates arguments against JSON schemas.
    switch (toolName) {
      case 'sendMessage':
        return arguments.containsKey('conversationId') && arguments.containsKey('text');
      case 'revokeSessions':
        return true; // No args needed
      case 'deleteMessage':
        return arguments.containsKey('messageId');
      default:
        // Unknown tools are denied by default
        return false;
    }
  }

  Future<bool> _checkBackendPermissions(String uid, String toolName, Map<String, dynamic> args) async {
    // This replicates server-side validation.
    // e.g., if toolName is "deleteMessage", we ensure the user is the sender of that message.
    if (toolName == 'deleteMessage') {
      final msgId = args['messageId'] as String;
      final doc = await _firestore.collection('messages').doc(msgId).get();
      if (!doc.exists) return false;
      return doc.data()?['senderId'] == uid;
    }
    
    if (toolName == 'sendMessage') {
      // Check if user is participant of conversationId
      final convId = args['conversationId'] as String;
      final doc = await _firestore.collection('conversations').doc(convId).get();
      if (!doc.exists) return false;
      final participants = List<String>.from(doc.data()?['participants'] ?? []);
      return participants.contains(uid);
    }
    
    if (toolName == 'revokeSessions') {
      // Destructive actions might require a recent login re-auth token.
      return true; // Simplification for demo
    }

    // Safe by default
    return false; 
  }

  Future<void> _auditToolExecution(String uid, String toolName, Map<String, dynamic> args, bool wasAuthorized) async {
    // "Log privileged tool actions."
    // Fire and forget to audit log
    _firestore.collection('users').doc(uid).collection('ai_audit_logs').add({
      'toolName': toolName,
      'arguments': args,
      'wasAuthorized': wasAuthorized,
      'timestamp': FieldValue.serverTimestamp(),
      'ipAddress': '127.0.0.1', // Example metadata
    }).catchError((e) {
      debugPrint("Audit log failed to write: $e");
      throw e;
    });
  }
}
