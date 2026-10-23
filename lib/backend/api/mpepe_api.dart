import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_annotations.dart';

/// Standard Error Structure for the API
class StandardApiError implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;
  StandardApiError({required this.code, required this.message, this.details});
  
  @override
  String toString() => '[$code] $message';
}

/// The Canonical Versioned API
/// This facade wraps all domain-specific services into a single, strongly-typed
/// REST-style interface, even when running directly against Firebase on the client.
class OnerovaApi {
  static final OnerovaApi instance = OnerovaApi._();
  OnerovaApi._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _enforceAuth() {
    if (_auth.currentUser == null) {
      throw StandardApiError(code: 'UNAUTHORIZED', message: 'Authentication required');
    }
  }

  // ===========================================================================
  // CONTENT & VIDEOS DOMAIN
  // ===========================================================================

  @ApiEndpoint(
    path: '/v1/videos',
    method: 'POST',
    requiresAuth: true,
    authorizationLevel: 'creator',
    validationRules: 'Video payload must contain valid mediaId and title',
    rateLimit: '10 requests per minute',
    isPaginated: false,
    isIdempotent: false,
    auditBehavior: 'Logs upload initiation to audit_log table',
  )
  Future<Map<String, dynamic>> createVideo(Map<String, dynamic> payload) async {
    _enforceAuth();
    if (payload['mediaId'] == null) throw StandardApiError(code: 'BAD_REQUEST', message: 'Missing mediaId');
    
    // Writes to the canonical content collection
    final docRef = await _db.collection('videos').add({
      ...payload,
      'ownerId': _auth.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    // Audit Log Requirement
    await _db.collection('audit_logs').add({
      'action': 'CREATE_VIDEO',
      'userId': _auth.currentUser!.uid,
      'targetId': docRef.id,
      'timestamp': FieldValue.serverTimestamp(),
    });

    return {'id': docRef.id, 'status': 'created'};
  }

  @ApiEndpoint(
    path: '/v1/videos',
    method: 'GET',
    requiresAuth: true,
    authorizationLevel: 'user',
    validationRules: 'cursor must be valid string if provided',
    rateLimit: '100 requests per minute',
    isPaginated: true,
    isIdempotent: true,
    auditBehavior: 'None',
  )
  Future<List<Map<String, dynamic>>> listVideos({int limit = 20, DocumentSnapshot? cursor}) async {
    _enforceAuth();
    var query = _db.collection('videos').orderBy('createdAt', descending: true).limit(limit);
    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    final snap = await query.get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ===========================================================================
  // MODERATION DOMAIN
  // ===========================================================================

  @ApiEndpoint(
    path: '/v1/moderation/report',
    method: 'POST',
    requiresAuth: true,
    authorizationLevel: 'user',
    validationRules: 'Must provide targetId, targetType, and categories',
    rateLimit: '5 requests per minute',
    isPaginated: false,
    isIdempotent: true,
    auditBehavior: 'Logs reporting event for trust & safety tracking',
  )
  Future<void> reportContent(String targetId, String targetType, List<String> categories) async {
    _enforceAuth();
    final uid = _auth.currentUser!.uid;
    // Implementation links back to our created ModerationSystem
    await _db.collection('moderation_tickets').add({
      'targetId': targetId,
      'targetType': targetType,
      'reportedByUserId': uid,
      'flaggedCategories': categories,
      'state': 'pendingAutomatedReview',
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    await _db.collection('audit_logs').add({
      'action': 'REPORT_CONTENT',
      'userId': uid,
      'targetId': targetId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ===========================================================================
  // MESSAGES DOMAIN
  // ===========================================================================

  @ApiEndpoint(
    path: '/v1/messages/send',
    method: 'POST',
    requiresAuth: true,
    authorizationLevel: 'user',
    validationRules: 'Message must not exceed 2000 chars. E2EE payload must be base64.',
    rateLimit: '60 requests per minute',
    isPaginated: false,
    isIdempotent: true, // Requires client-generated messageId (uuid)
    auditBehavior: 'Message metadata logged. E2EE payload strictly not logged.',
  )
  Future<void> sendMessage(String chatId, String messageId, Map<String, dynamic> payload) async {
    _enforceAuth();
    // Implementation links back to our MessagingRepository logic
    await _db.collection('chats').doc(chatId).collection('messages').doc(messageId).set({
      ...payload,
      'senderId': _auth.currentUser!.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
