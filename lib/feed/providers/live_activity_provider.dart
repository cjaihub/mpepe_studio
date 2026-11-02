import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/social/models/comment.dart';
import '../../shared/theme/app_theme.dart';

/// User privacy setting for real-time live presence and activity broadcasting
enum LivePresencePrivacy {
  /// Public: actions appear in live floating cards & stage ticker for all attendees
  publicSpotlight,
  /// Connections only: only followers & mutuals see live activity cards
  connectionsOnly,
  /// Ghost Mode: 100% incognito. Never shown in live stream cards or audience tickers
  ghostMode;

  static LivePresencePrivacy fromString(String? val) {
    switch (val) {
      case 'connections':
      case 'connectionsOnly':
        return LivePresencePrivacy.connectionsOnly;
      case 'ghost':
      case 'ghostMode':
        return LivePresencePrivacy.ghostMode;
      case 'public':
      case 'publicSpotlight':
      default:
        return LivePresencePrivacy.publicSpotlight;
    }
  }

  String toFirestoreValue() {
    switch (this) {
      case LivePresencePrivacy.connectionsOnly:
        return 'connections';
      case LivePresencePrivacy.ghostMode:
        return 'ghost';
      case LivePresencePrivacy.publicSpotlight:
        return 'public';
    }
  }

  String get displayName {
    switch (this) {
      case LivePresencePrivacy.publicSpotlight:
        return 'Public Spotlight';
      case LivePresencePrivacy.connectionsOnly:
        return 'Connections Only';
      case LivePresencePrivacy.ghostMode:
        return 'Ghost Mode (Incognito)';
    }
  }

  String get description {
    switch (this) {
      case LivePresencePrivacy.publicSpotlight:
        return 'Your live reactions, remixes, and joins appear in floating cards for all viewers.';
      case LivePresencePrivacy.connectionsOnly:
        return 'Only people you follow or mutual connections see your live activity cards.';
      case LivePresencePrivacy.ghostMode:
        return 'Complete stealth. You can watch and interact without your name appearing in live logs.';
    }
  }

  IconData get icon {
    switch (this) {
      case LivePresencePrivacy.publicSpotlight:
        return Icons.campaign_rounded;
      case LivePresencePrivacy.connectionsOnly:
        return Icons.people_alt_rounded;
      case LivePresencePrivacy.ghostMode:
        return Icons.visibility_off_rounded;
    }
  }

  Color get color {
    switch (this) {
      case LivePresencePrivacy.publicSpotlight:
        return AppColors.brandBlue;
      case LivePresencePrivacy.connectionsOnly:
        return AppColors.brandPink;
      case LivePresencePrivacy.ghostMode:
        return const Color(0xFFFFB300);
    }
  }
}

/// A structured live activity card event for floating visual cards
class LiveActivityCardItem {
  final String id;
  final String type;
  final String userId;
  final String username;
  final String avatarUrl;
  final String message;
  final IconData icon;
  final Color badgeColor;
  final DateTime timestamp;
  final double rotationAngle; // Slight organic tilt (-0.035 to +0.035 rad)
  final bool isVerified;

  /// Set for voice comments: [message] is then empty and this is the audio.
  final String? voiceUrl;
  final int? voiceDurationMs;

  /// Set for GIF comments so floating reel pills render a mini GIF preview.
  final CommentGif? gif;

  const LiveActivityCardItem({
    required this.id,
    required this.type,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.message,
    required this.icon,
    required this.badgeColor,
    required this.timestamp,
    required this.rotationAngle,
    this.isVerified = false,
    this.voiceUrl,
    this.voiceDurationMs,
    this.gif,
  });
}

class LivePresencePrivacyNotifier extends Notifier<LivePresencePrivacy> {
  @override
  LivePresencePrivacy build() {
    _loadFromFirestore();
    return LivePresencePrivacy.publicSpotlight;
  }

  Future<void> _loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final val = doc.data()?['livePresenceVisibility'] as String?;
        if (val != null) {
          state = LivePresencePrivacy.fromString(val);
        }
      }
    } catch (_) {}
  }

  Future<void> updatePrivacy(LivePresencePrivacy privacy) async {
    state = privacy;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'livePresenceVisibility': privacy.toFirestoreValue(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// Provider managing the current user's live presence privacy
final livePresencePrivacyProvider = NotifierProvider<LivePresencePrivacyNotifier, LivePresencePrivacy>(
  LivePresencePrivacyNotifier.new,
);

/// Real-time live social events stream with privacy enforcement
final liveSocialEventsStreamProvider = StreamProvider.autoDispose<List<LiveActivityCardItem>>((ref) {
  final firestore = FirebaseFirestore.instance;

  return firestore
      .collection('social_events')
      .orderBy('timestamp', descending: true)
      .limit(10)
      .snapshots()
      .map((snapshot) {
    final items = <LiveActivityCardItem>[];

    for (var i = 0; i < snapshot.docs.length; i++) {
      final doc = snapshot.docs[i];
      final data = doc.data();
      final type = data['type'] as String? ?? 'activity';
      final payload = data['payload'] as Map<String, dynamic>? ?? {};

      // Privacy check: skip if sender set privacy to ghost or private
      final privacy = payload['privacy'] as String?;
      if (privacy == 'ghost' || payload['isPrivate'] == true) {
        continue;
      }

      final userId = payload['userId'] as String? ?? payload['followerId'] as String? ?? '';
      final username = payload['username'] as String? ??
          (userId.isNotEmpty ? 'User_${userId.substring(0, min(4, userId.length))}' : 'Attendee');
      final avatarUrl = payload['avatarUrl'] as String? ?? '';

      String message;
      IconData icon;
      Color badgeColor;

      if (type.contains('liked')) {
        message = 'liked this reel';
        icon = Icons.favorite_rounded;
        badgeColor = AppColors.brandPink;
      } else if (type.contains('comment')) {
        message = 'commented live';
        icon = Icons.chat_bubble_rounded;
        badgeColor = AppColors.brandBlue;
      } else if (type.contains('remixed') || type.contains('audio')) {
        message = 'remixed this sound';
        icon = Icons.music_note_rounded;
        badgeColor = AppColors.brandPink;
      } else if (type.contains('followed') || type.contains('stage.joined')) {
        message = 'joined live stage';
        icon = Icons.mic_rounded;
        badgeColor = AppColors.brandBlue;
      } else if (type.contains('cheer') || type.contains('gift')) {
        message = 'cheered 50 gems';
        icon = Icons.diamond_rounded;
        badgeColor = AppColors.brandPink;
      } else {
        message = 'shared reaction';
        icon = Icons.auto_awesome_rounded;
        badgeColor = (i % 2 == 0) ? AppColors.brandBlue : AppColors.brandPink;
      }

      // Organic rotation between -2.2° (-0.038 rad) and +2.2° (+0.038 rad)
      final angles = [-0.032, 0.026, -0.018, 0.035, -0.024, 0.020];
      final rotationAngle = angles[i % angles.length];

      final isVerified = payload['isVerified'] == true;

      final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

      items.add(
        LiveActivityCardItem(
          id: doc.id,
          type: type,
          userId: userId,
          username: username,
          avatarUrl: avatarUrl,
          message: message,
          icon: icon,
          badgeColor: badgeColor,
          timestamp: ts,
          rotationAngle: rotationAngle,
          isVerified: isVerified,
        ),
      );
    }

    return items;
  });
});

/// Real-time counter to trigger celebratory glowing love bursts across reel overlays
class GlowingLoveBurstNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final glowingLoveBurstProvider =
    NotifierProvider<GlowingLoveBurstNotifier, int>(GlowingLoveBurstNotifier.new);

class _CachedAuthor {
  final String username;
  final String avatarUrl;
  final bool isVerified;
  final DateTime fetchedAt;

  const _CachedAuthor({
    required this.username,
    required this.avatarUrl,
    required this.isVerified,
    required this.fetchedAt,
  });
}

final Map<String, _CachedAuthor> _authorMemo = {};

Future<_CachedAuthor> _resolveAuthor(FirebaseFirestore firestore, String uid, {String fallback = 'Fan'}) async {
  if (uid.isEmpty) {
    return _CachedAuthor(username: fallback, avatarUrl: '', isVerified: false, fetchedAt: DateTime.now());
  }
  final cached = _authorMemo[uid];
  if (cached != null && DateTime.now().difference(cached.fetchedAt) < const Duration(minutes: 5)) {
    return cached;
  }
  final shortFallback = 'User_${uid.substring(0, min(4, uid.length))}';
  try {
    final uDoc = await firestore.collection('users').doc(uid).get();
    if (uDoc.exists) {
      final uData = uDoc.data();
      final resolved = _CachedAuthor(
        username: (uData?['username'] as String?)?.isNotEmpty == true
            ? uData!['username'] as String
            : ((uData?['displayName'] as String?)?.isNotEmpty == true
                  ? uData!['displayName'] as String
                  : ((uData?['fullName'] as String?)?.isNotEmpty == true
                        ? uData!['fullName'] as String
                        : shortFallback)),
        avatarUrl: uData?['profilePhotoUrl'] as String? ?? '',
        isVerified: uData?['isVerified'] == true,
        fetchedAt: DateTime.now(),
      );
      _authorMemo[uid] = resolved;
      return resolved;
    }
  } catch (_) {}
  final def = _CachedAuthor(username: shortFallback, avatarUrl: '', isVerified: false, fetchedAt: DateTime.now());
  _authorMemo[uid] = def;
  return def;
}

/// Content-specific live activity stream: feeds real comments (text, GIF, voice)
/// and deduplicated recent likes for the active reel into floating micro-cards.
final contentLiveActivityStreamProvider =
    StreamProvider.autoDispose.family<List<LiveActivityCardItem>, String>((ref, contentId) {
  final firestore = FirebaseFirestore.instance;

  return firestore
      .collection('posts')
      .doc(contentId)
      .collection('comments')
      .orderBy('createdAt', descending: true)
      .limit(25)
      .snapshots()
      .asyncMap((postCommentSnap) async {
    final commentDocsById = <String, Map<String, dynamic>>{};
    for (final doc in postCommentSnap.docs) {
      commentDocsById[doc.id] = doc.data();
    }

    // Fallback / merge from content/{id}/comments when posts/{id}/comments has fewer entries
    if (commentDocsById.isEmpty) {
      try {
        final contentCommentSnap = await firestore
            .collection('content')
            .doc(contentId)
            .collection('comments')
            .orderBy('createdAt', descending: true)
            .limit(25)
            .get();
        for (final doc in contentCommentSnap.docs) {
          commentDocsById.putIfAbsent(doc.id, doc.data);
        }
      } catch (_) {}
    }

    // Legacy top-level comments fallback
    if (commentDocsById.isEmpty) {
      try {
        final legacySnap = await firestore
            .collection('comments')
            .where('postId', isEqualTo: contentId)
            .limit(15)
            .get();
        for (final doc in legacySnap.docs) {
          commentDocsById.putIfAbsent(doc.id, doc.data);
        }
      } catch (_) {}
    }

    final commentItems = <LiveActivityCardItem>[];
    final entries = commentDocsById.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final docId = entries[i].key;
      final data = entries[i].value;
      if (data['isModerated'] == true) continue;

      final authorId = data['authorId'] as String? ?? '';
      final rawText = (data['content'] as String? ?? '').trim();
      final isVoice = data['type'] == 'voice';
      CommentGif? gif = CommentGif.fromMap(data['gif']);
      if (gif == null && data['type'] == 'gif' && rawText.startsWith('https://')) {
        gif = CommentGif(id: docId, url: rawText, w: 220, h: 220);
      }
      final displayText = (data['type'] == 'gif' && rawText == gif?.url) ? '' : rawText;

      if (displayText.isEmpty && gif == null && !isVoice) continue;

      final author = await _resolveAuthor(firestore, authorId);
      final angles = [-0.015, 0.012, -0.010, 0.014, -0.012, 0.010];
      final ts = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

      commentItems.add(
        LiveActivityCardItem(
          id: 'c_$docId',
          type: gif != null ? 'reel.gif_comment' : 'reel.comment',
          userId: authorId,
          username: author.username,
          avatarUrl: author.avatarUrl,
          message: isVoice ? '' : displayText,
          icon: isVoice
              ? Icons.graphic_eq_rounded
              : gif != null
                  ? Icons.gif_box_rounded
                  : Icons.chat_bubble_rounded,
          badgeColor: AppColors.brandBlue,
          timestamp: ts,
          rotationAngle: angles[i % angles.length],
          isVerified: author.isVerified,
          voiceUrl: isVoice ? rawText : null,
          voiceDurationMs: isVoice ? (data['voiceDurationMs'] as num?)?.toInt() : null,
          gif: gif,
        ),
      );
    }

    // 2. Recent likes on this reel (deduplicated per userId)
    final likeItems = <LiveActivityCardItem>[];
    final seenLikers = <String>{};
    try {
      final likeSnap = await firestore
          .collection('content_likes')
          .where('contentId', isEqualTo: contentId)
          .limit(20)
          .get();

      for (var j = 0; j < likeSnap.docs.length; j++) {
        final lDoc = likeSnap.docs[j];
        final lData = lDoc.data();
        final lUserId = lData['userId'] as String? ?? '';
        if (lUserId.isEmpty || !seenLikers.add(lUserId)) continue;

        final author = await _resolveAuthor(firestore, lUserId);
        final angles = [0.012, -0.014, 0.010, -0.015];
        likeItems.add(
          LiveActivityCardItem(
            id: 'l_${lDoc.id}',
            type: 'reel.liked',
            userId: lUserId,
            username: author.username,
            avatarUrl: author.avatarUrl,
            message: 'liked this reel',
            icon: Icons.favorite_rounded,
            badgeColor: AppColors.brandPink,
            timestamp: (lData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            rotationAngle: angles[j % angles.length],
            isVerified: author.isVerified,
          ),
        );
      }
    } catch (_) {}

    // Interleave comments first with occasional likes so comments lead the stream
    commentItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    likeItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final merged = <LiveActivityCardItem>[];
    var ci = 0;
    var li = 0;
    while (ci < commentItems.length || li < likeItems.length) {
      if (ci < commentItems.length) merged.add(commentItems[ci++]);
      if (ci < commentItems.length) merged.add(commentItems[ci++]);
      if (li < likeItems.length) merged.add(likeItems[li++]);
    }
    return merged;
  });
});

/// Service method to publish live presence reactions, cheers, or bubble bursts
Future<void> emitLiveReactionEvent({
  required String contentId,
  required String reactionType,
  required WidgetRef ref,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final uid = user?.uid ?? 'guest';
  final privacy = ref.read(livePresencePrivacyProvider);

  // If in ghost mode, skip publishing public live activity event
  if (privacy == LivePresencePrivacy.ghostMode) return;

  try {
    String username = 'Creator';
    String avatarUrl = '';
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        username = doc.data()?['username'] ?? user.displayName ?? 'Creator';
        avatarUrl = doc.data()?['profilePhotoUrl'] ?? user.photoURL ?? '';
      }
    }

    await FirebaseFirestore.instance.collection('social_events').add({
      'type': 'stage.reaction',
      'payload': {
        'userId': uid,
        'username': username,
        'avatarUrl': avatarUrl,
        'contentId': contentId,
        'reaction': reactionType,
        'privacy': privacy.toFirestoreValue(),
      },
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}
