import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What kind of item was shared during a call.
enum CallShareKind { image, video, file }

/// One photo, video or file sent during a call, stored in
/// `calls/{callId}/shared/{id}`.
class CallSharedItem {
  final String id;
  final String senderId;
  final String senderName;
  final String name;
  final String url;
  final CallShareKind kind;
  final int size;
  final DateTime createdAt;

  const CallSharedItem({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.name,
    required this.url,
    required this.kind,
    required this.size,
    required this.createdAt,
  });

  factory CallSharedItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return CallSharedItem(
      id: doc.id,
      senderId: (d['senderId'] ?? '') as String,
      senderName: (d['senderName'] ?? '') as String,
      name: (d['name'] ?? 'File') as String,
      url: (d['url'] ?? '') as String,
      kind: CallShareKind.values.firstWhere(
        (k) => k.name == d['kind'],
        orElse: () => CallShareKind.file,
      ),
      size: (d['size'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

final callShareServiceProvider = Provider<CallShareService>((ref) => CallShareService());

/// Live stream of everything shared in a call, newest first.
final callSharedItemsProvider =
    StreamProvider.autoDispose.family<List<CallSharedItem>, String>((ref, callId) {
  return ref.read(callShareServiceProvider).watch(callId);
});

/// Uploads files to Storage and announces them to the other participants.
///
/// Files go under `chats/{chatId}/attachments/` (the call's chat, or
/// `call_{callId}` for calls placed outside a chat), which the existing
/// storage rules already allow for signed-in users.
class CallShareService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const int maxBytes = 200 * 1024 * 1024;

  CollectionReference<Map<String, dynamic>> _col(String callId) =>
      _firestore.collection('calls').doc(callId).collection('shared');

  Stream<List<CallSharedItem>> watch(String callId) => _col(callId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(CallSharedItem.fromFirestore).toList());

  static CallShareKind kindFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'};
    const videos = {'mp4', 'mov', 'm4v', '3gp', 'mkv', 'webm', 'avi'};
    if (images.contains(ext)) return CallShareKind.image;
    if (videos.contains(ext)) return CallShareKind.video;
    return CallShareKind.file;
  }

  static String? _contentType(String path, CallShareKind kind) {
    final ext = path.split('.').last.toLowerCase();
    switch (kind) {
      case CallShareKind.image:
        return ext == 'png' ? 'image/png' : (ext == 'gif' ? 'image/gif' : 'image/jpeg');
      case CallShareKind.video:
        return ext == 'mov' ? 'video/quicktime' : 'video/mp4';
      case CallShareKind.file:
        return ext == 'pdf' ? 'application/pdf' : null;
    }
  }

  /// Uploads [file] and posts it to the call. [onProgress] gets 0..1.
  Future<void> share({
    required String callId,
    String? chatId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to share files.');
    final size = await file.length();
    if (size > maxBytes) throw StateError('Files must be under 200 MB.');

    final name = file.path.split(Platform.pathSeparator).last;
    final kind = kindFor(name);
    final folder = (chatId != null && chatId.isNotEmpty) ? chatId : 'call_$callId';
    final ref = _storage
        .ref('chats/$folder/attachments/call_${DateTime.now().millisecondsSinceEpoch}_$name');
    final task = ref.putFile(
      file,
      SettableMetadata(contentType: _contentType(name, kind)),
    );
    final sub = task.snapshotEvents.listen((s) {
      if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
    });
    try {
      await task;
    } finally {
      await sub.cancel();
    }
    final url = await ref.getDownloadURL();
    await _col(callId).add({
      'senderId': user.uid,
      'senderName': user.displayName ?? '',
      'name': name,
      'url': url,
      'kind': kind.name,
      'size': size,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
